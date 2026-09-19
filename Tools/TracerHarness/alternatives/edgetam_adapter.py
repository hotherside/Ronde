#!/usr/bin/env python3
"""Official EdgeTAM comparator using private lossless AVFoundation frame caches.

One supplied point prompts one object. Raw masks are retained privately. The
largest 8-connected component of logits > 0 supplies its unweighted pixel-centre
centroid; an empty mask emits no point. No labels, smoothing or fitting are used.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import sys
import time


def external(path: str | Path) -> Path:
    path = Path(path).expanduser().resolve()
    if path.is_relative_to(Path(__file__).resolve().parents[3]):
        raise ValueError("Private inputs, models and outputs must remain outside the repository")
    return path


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda:stream.read(1024*1024), b""):
            h.update(block)
    return h.hexdigest()


def run() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--config",type=Path,required=True)
    p.add_argument("--edgetam-root",type=Path,required=True)
    p.add_argument("--checkpoint",type=Path,required=True)
    p.add_argument("--output",type=Path,required=True)
    p.add_argument("--device",choices=("mps","cpu"),default="mps")
    p.add_argument("--max-frames",type=int)
    args = p.parse_args()
    started = time.perf_counter()
    executed_adapter_sha256 = digest(Path(__file__))
    config_path,upstream,checkpoint,output = map(external,
        (args.config,args.edgetam_root,args.checkpoint,args.output))
    config = json.loads(config_path.read_text())
    cache_path = external(config["frame_cache_manifest"])
    source_manifest_path = external(config["avfoundation_frame_manifest"])
    source_path = external(config["source_path"])
    cache = json.loads(cache_path.read_text())
    source_manifest = json.loads(source_manifest_path.read_text())
    width,height = cache["width"],cache["height"]
    if (width,height) != (source_manifest["width"],source_manifest["height"]):
        raise ValueError("AV cache and source manifest dimensions differ")
    crop = tuple(config["crop_xywh"])
    if len(crop)!=4 or any(type(v) is not int for v in crop) or min(crop[2:])<=0:
        raise ValueError("Fixed crop must contain integer origin and positive dimensions")
    if min(crop[:2])<0 or crop[0]+crop[2]>width or crop[1]+crop[3]>height:
        raise ValueError("Fixed crop is outside the upright source")
    frames = [r for r in cache["frames"]
              if config["start_time_seconds"] <= r["timestamp"] <= config["end_time_seconds"]]
    if args.max_frames:
        if args.max_frames<2:raise ValueError("At least two frames are required")
        frames = frames[:args.max_frames]
    if len(frames)<2:raise ValueError("Selected source interval is too short")
    for i,frame in enumerate(frames):
        if abs(source_manifest["frameTimes"][frame["frameIndex"]]-frame["timestamp"])>1e-6:
            raise ValueError("Source PTS does not exactly match the AVFoundation manifest")
        if i and (frame["frameIndex"]!=frames[i-1]["frameIndex"]+1
                  or frame["timestamp"]<=frames[i-1]["timestamp"]):
            raise ValueError("Frames must be consecutive with increasing source PTS")
        left,top = crop[0]-frame["cropX"],crop[1]-frame["cropY"]
        if min(left,top)<0 or left+crop[2]>frame["cropWidth"] or top+crop[3]>frame["cropHeight"]:
            raise ValueError("Fixed crop is not contained in the source cache")
        external(cache_path.parent/frame["file"])
    if len(config["prompts"])!=1 or config.get("correction_count",0)!=0:
        raise ValueError("Exactly one point and no corrections are supported")
    prompt = config["prompts"][0]
    seed_index = min(range(len(frames)),key=lambda i:abs(frames[i]["timestamp"]-prompt["time_seconds"]))
    if abs(frames[seed_index]["timestamp"]-prompt["time_seconds"])>.001:
        raise ValueError("Point must refer to a selected actual source PTS within 1 ms")
    query = [prompt["x_px"]-crop[0],prompt["y_px"]-crop[1]]
    if not 0<=query[0]<crop[2] or not 0<=query[1]<crop[3]:
        raise ValueError("Point lies outside the fixed source crop")
    sys.path.insert(0,str(upstream))
    import numpy as np
    from PIL import Image
    from scipy import ndimage
    import torch
    import sam2.sam2_video_predictor as predictor_module
    import sam2.modeling.backbones.timm as backbone_module
    from sam2.build_sam import build_sam2_video_predictor
    if args.device=="mps" and not torch.backends.mps.is_available():
        raise RuntimeError("MPS requested but unavailable")

    # The full checkpoint replaces every backbone parameter. Avoid the upstream
    # constructor's redundant remote timm pretrained download before strict load.
    original_create_model = backbone_module.create_model
    def local_backbone(*values,**kwargs):
        kwargs["pretrained"] = False
        return original_create_model(*values,**kwargs)
    backbone_module.create_model = local_backbone
    overrides = [
        "++model.sam_mask_decoder_extra_args.dynamic_multimask_via_stability=true",
        "++model.sam_mask_decoder_extra_args.dynamic_multimask_stability_delta=0.05",
        "++model.sam_mask_decoder_extra_args.dynamic_multimask_stability_thresh=0.98",
        "++model.binarize_mask_from_pts_for_mem_enc=true",
        "++model.fill_hole_area=0",
    ]
    try:
        predictor = build_sam2_video_predictor("configs/edgetam.yaml",str(checkpoint),
            device=args.device,apply_postprocessing=False,hydra_overrides_extra=overrides)
    finally:
        backbone_module.create_model = original_create_model
    assert predictor.fill_hole_area==0
    class LosslessFrames:
        def __len__(self):return len(frames)
        def __getitem__(self,index):
            f=frames[index]
            with Image.open(external(cache_path.parent/f["file"])) as im:
                left,top=crop[0]-f["cropX"],crop[1]-f["cropY"]
                im=im.convert("RGB").crop((left,top,left+crop[2],top+crop[3]))
                im=im.resize((predictor.image_size,predictor.image_size),Image.Resampling.BICUBIC)
                array=np.asarray(im).copy()
            tensor=torch.from_numpy(array).permute(2,0,1).float()/255.0
            return (tensor-torch.tensor([.485,.456,.406])[:,None,None])/torch.tensor([.229,.224,.225])[:,None,None]
    images=LosslessFrames()
    def load_lossless(**kwargs):
        return images,crop[3],crop[2]
    original_loader=predictor_module.load_video_frames
    predictor_module.load_video_frames=load_lossless
    output.parent.mkdir(parents=True,exist_ok=True)
    mask_dir=external(output.parent/(output.stem+"-masks"))
    mask_dir.mkdir(exist_ok=True)
    samples={}
    setup_done=time.perf_counter()
    print(json.dumps({"stage":"model_ready","frames":len(frames),"crop_size":crop[2:],
                      "model_input_size":predictor.image_size,"setup_seconds":setup_done-started}),flush=True)
    def retain(index,logits,state,direction):
        values=logits[0,0].detach().float().cpu().numpy()
        if values.shape!=(crop[3],crop[2]) or not np.isfinite(values).all():
            raise RuntimeError("Unexpected or non-finite mask output")
        foreground=values>0
        labels,count=ndimage.label(foreground,structure=np.ones((3,3),dtype=np.uint8))
        areas=np.bincount(labels.ravel());areas[0]=0
        component=int(areas.argmax()) if count else 0
        frame=frames[index]
        record={"timestamp":frame["timestamp"],"sourceFrameIndex":frame["frameIndex"],
                "visible":bool(component),"componentCount":int(count),
                "rawPositiveMaskAreaPx":int(foreground.sum()),
                "selectedComponentAreaPx":int(areas[component]) if component else 0,
                "maximumMaskLogit":float(values.max()),"direction":direction}
        stored=state["output_dict"]["cond_frame_outputs"].get(index)
        if stored is None:stored=state["output_dict"]["non_cond_frame_outputs"].get(index)
        confidence=None
        if stored is not None and "object_score_logits" in stored:
            logit=float(stored["object_score_logits"].detach().float().cpu().flatten()[0])
            record["objectScoreLogit"]=logit
            confidence=1/(1+math.exp(-max(-80,min(80,logit))))
            record["confidence"]=confidence
        if component:
            ys,xs=np.nonzero(labels==component)
            record.update({"x":float(xs.mean()+.5+crop[0])/width,
                           "y":float(ys.mean()+.5+crop[1])/height,
                           "meanComponentMaskLogit":float(values[labels==component].mean())})
        mask_file=mask_dir/f"frame-{frame['frameIndex']:04d}.png"
        Image.fromarray(foreground.astype(np.uint8)*255).save(mask_file)
        record["rawBinaryMaskPath"]=str(mask_file)
        samples[index]=record
    try:
        with torch.inference_mode():
            for reverse in ([False,True] if seed_index>0 else [False]):
                state=predictor.init_state("private-lossless-av-cache",offload_video_to_cpu=True,
                                           offload_state_to_cpu=False)
                predictor.add_new_points_or_box(state,frame_idx=seed_index,obj_id=1,
                    points=np.array([query],dtype=np.float32),labels=np.array([1],dtype=np.int32))
                for index,ids,logits in predictor.propagate_in_video(state,start_frame_idx=seed_index,
                                                                    reverse=reverse):
                    if reverse and index==seed_index:continue
                    retain(index,logits,state,"reverse" if reverse else "forward")
                del state
            if args.device=="mps":torch.mps.synchronize()
    finally:
        predictor_module.load_video_frames=original_loader
    finished=time.perf_counter()
    ordered=[samples[i] for i in sorted(samples)]
    if len(ordered)!=len(frames):raise RuntimeError("Not every selected source frame was processed")
    timing_prompts=int("controlled_impact_time" in config)
    result={"schemaVersion":"1.0","clipId":config["clip_id"],
        "sourceHash":"sha256:"+digest(source_path),"width":width,"height":height,
        "coordinateOrigin":"top-left","coordinateSpace":"normalized","mode":"assisted",
        "promptCount":1+timing_prompts,"pointPromptCount":1,"timingPromptCount":timing_prompts,
        "correctionCount":0,"frames":[{k:s[k] for k in ("timestamp","x","y","confidence") if k in s}
                                      for s in ordered if s["visible"]],"samples":ordered,
        "assistance":{"pointPrompt":prompt,"actualPromptTimestamp":frames[seed_index]["timestamp"],
            "crop_xywh":crop,"crop_type":config["crop_type"],"crop_rationale":config["crop_rationale"],
            "suppliedInterval":True,"usesFutureEvidence":seed_index>0,"correctionCount":0},
        "model":{"name":"official_EdgeTAM","upstreamCommit":subprocess.check_output(
            ["git","-C",str(upstream),"rev-parse","HEAD"],text=True).strip(),
            "checkpointSHA256":digest(checkpoint),"licence":"Apache-2.0 code and checkpoints",
            "parameterCount":sum(x.numel() for x in predictor.parameters()),
            "adapterSHA256":executed_adapter_sha256,"configurationSHA256":digest(config_path)},
        "processing":{"device":args.device,"platform":platform.platform(),"python":platform.python_version(),
            "packageVersions":{name:importlib.metadata.version(name) for name in
                               ("torch","torchvision","numpy","pillow","scipy","timm","hydra-core")},
            "parameterDtype":str(next(predictor.parameters()).dtype),
            "modelInputSize":[predictor.image_size,predictor.image_size],"sourceCropSize":crop[2:],
            "losslessAVCache":True,"sourceFramesConsecutive":True,"sourcePTSVerified":True,
            "inputResize":"Pillow bicubic direct native crop to official square input",
            "customInputLoaderOnly":True,"offloadVideoToCPU":True,
            "mpsFallbackEnabled":os.environ.get("PYTORCH_ENABLE_MPS_FALLBACK")=="1",
            "cudaExtensionBuilt":False,"cudaHoleFillingDisabled":True,
            "otherPostprocessing":"Official stability multimask and prompt-memory binarisation defaults retained",
            "redundantPretrainedBackboneDownloadDisabled":True,
            "maskRule":"logits > 0; largest 8-connected positive component; unweighted pixel-centre centroid; no area gate; empty mask abstains",
            "confidenceInterpretation":"Object-presence score, not calibrated golf localisation correctness",
            "setupSeconds":setup_done-started,"propagationAndMaskExportSeconds":finished-setup_done,
            "totalSecondsBeforeSerialisation":finished-started}}
    # Scalar aliases survive the benchmark report's metadata allowlist.
    result.update({"upstream_commit":result["model"]["upstreamCommit"],
                   "checkpoint_sha256":result["model"]["checkpointSHA256"],
                   "adapterCodeSHA256":result["model"]["adapterSHA256"]})
    output.write_text(json.dumps(result,indent=2)+"\n")
    print(json.dumps({"stage":"complete","sourceFrames":len(frames),"nonemptyMasks":len(result["frames"]),
                      "propagationAndMaskExportSeconds":finished-setup_done}),flush=True)


if __name__=="__main__":run()
