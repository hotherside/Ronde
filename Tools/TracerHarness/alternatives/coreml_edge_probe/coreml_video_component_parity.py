#!/usr/bin/env python3
"""CPU video component-substitution parity probe for pinned EdgeTAM packages."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, platform, sys, time, traceback
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
ADAPTER = REPO / "Tools" / "TracerHarness" / "alternatives" / "edgetam_adapter.py"

def outside(path: Path) -> Path:
    path = path.expanduser().resolve()
    if path == REPO or REPO in path.parents: raise ValueError("private inputs and outputs must be outside repository")
    return path

def sha(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda:f.read(1048576),b""):h.update(block)
    return h.hexdigest()

def tree_sha(path: Path) -> str:
    h=hashlib.sha256()
    for item in sorted(x for x in path.rglob("*") if x.is_file()):
        h.update(item.relative_to(path).as_posix().encode()+b"\0"+sha(item).encode()+b"\n")
    return h.hexdigest()

def atomic_json(path: Path, value: dict) -> None:
    temporary=path.with_suffix(path.suffix+".tmp")
    temporary.write_text(json.dumps(value,indent=2)+"\n")
    temporary.replace(path)

def load_adapter():
    spec=importlib.util.spec_from_file_location("edge_adapter_for_component_parity",ADAPTER)
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

def run_adapter(adapter, config, source, checkpoint, output):
    old=sys.argv
    try:
        sys.argv=[str(ADAPTER),"--config",str(config),"--edgetam-root",str(source),"--checkpoint",str(checkpoint),"--output",str(output),"--device","cpu","--max-frames","32"]
        adapter.run()
    finally: sys.argv=old

def install_bridges(source, packages, stage):
    import coremltools as ct, numpy as np, torch
    from sam2.modeling.sam2_base import SAM2Base
    from sam2.modeling.memory_attention import MemoryAttention
    image=ct.models.MLModel(str(packages["image"]),compute_units=ct.ComputeUnit.ALL)
    attention=ct.models.MLModel(str(packages["attention"]),compute_units=ct.ComputeUnit.ALL)
    point=ct.models.MLModel(str(packages["point"]),compute_units=ct.ComputeUnit.ALL)
    no_point=ct.models.MLModel(str(packages["noPoint"]),compute_units=ct.ComputeUnit.ALL)
    memory={False:ct.models.MLModel(str(packages["trackingMemory"]),compute_units=ct.ComputeUnit.ALL),True:ct.models.MLModel(str(packages["pointMemory"]),compute_units=ct.ComputeUnit.ALL)}
    originals={"forward_image":SAM2Base.forward_image,"sam":SAM2Base._forward_sam_heads,"memory":SAM2Base._encode_new_memory,"attention":MemoryAttention.forward}
    def tensor(value, device): return torch.from_numpy(np.asarray(value)).to(device=device,dtype=torch.float32)
    def forward_image(self, image_normalised):
        before=time.perf_counter();raw=image.predict({"image_normalised":image_normalised.detach().float().cpu().numpy()});stage("image",time.perf_counter()-before)
        fpn=[tensor(raw["high_res_feat_0"],image_normalised.device),tensor(raw["high_res_feat_1"],image_normalised.device),tensor(raw["vision_features"],image_normalised.device)]
        positions=[self.image_encoder.neck.position_encoding(x).to(x.dtype) for x in fpn]
        return {"vision_features":fpn[-1],"vision_pos_enc":positions,"backbone_fpn":fpn}
    def attention_forward(self,curr,memory,curr_pos=None,memory_pos=None,num_obj_ptr_tokens=0,num_spatial_mem=-1):
        if isinstance(curr,list):
            if not isinstance(curr_pos,list) or len(curr)!=1 or len(curr_pos)!=1: raise RuntimeError("unsupported current feature list")
            curr,curr_pos=curr[0],curr_pos[0]
        memory_tokens=memory
        spatial=memory_tokens.shape[0]-num_obj_ptr_tokens
        if not (1<=num_spatial_mem<=7 and spatial==num_spatial_mem*512 and 4<=num_obj_ptr_tokens<=64 and num_obj_ptr_tokens%4==0): raise RuntimeError("unsupported attention state; require 1..7 whole 512-token spatial frames and 1..16 pointers")
        if curr.shape[1]!=1 or memory_tokens.shape[1]!=1: raise RuntimeError("one object/batch only")
        current=curr.permute(1,2,0).reshape(1,256,64,64); pos=curr_pos.permute(1,2,0).reshape(1,256,64,64)
        mem=memory_tokens.permute(1,0,2); mpos=memory_pos.permute(1,0,2)
        if torch.count_nonzero(mpos[:,spatial:]).item()!=0: raise RuntimeError("object pointer positional tokens must be zero")
        before=time.perf_counter();raw=attention.predict({"current_features":current.detach().float().cpu().numpy(),"current_position":pos.detach().float().cpu().numpy(),"spatial_memory":mem[:,:spatial].detach().float().cpu().numpy(),"spatial_memory_position":mpos[:,:spatial].detach().float().cpu().numpy(),"object_pointer_tokens":mem[:,spatial:].detach().float().cpu().numpy()});stage("attention",time.perf_counter()-before)
        return tensor(raw["fused_features"],curr.device).flatten(2).permute(2,0,1)
    def sam_heads(self,backbone_features,point_inputs=None,mask_inputs=None,high_res_features=None,multimask_output=False):
        if mask_inputs is not None or not multimask_output: raise RuntimeError("unsupported SAM mode: only no-mask multimask source modes")
        if point_inputs is None: model,values=no_point,{"backbone":backbone_features,"s0":high_res_features[0],"s1":high_res_features[1]}
        else:
            coords,labels=point_inputs["point_coords"],point_inputs["point_labels"]
            if tuple(coords.shape)!=(1,1,2) or tuple(labels.shape)!=(1,1) or int(labels.item())!=1: raise RuntimeError("only one positive point is supported")
            model,values=point,{"backbone_features":backbone_features,"high_res_s0":high_res_features[0],"high_res_s1":high_res_features[1],"point_coords":coords,"point_labels":labels}
        before=time.perf_counter();raw=model.predict({k:v.detach().float().cpu().numpy() if k!="point_labels" else v.detach().cpu().numpy() for k,v in values.items()});stage("sam_no_point" if point_inputs is None else "sam_point",time.perf_counter()-before)
        low=tensor(raw["low_best_256"],backbone_features.device); high=tensor(raw["high_best_1024"],backbone_features.device); iou=tensor(raw["ious"],backbone_features.device); ptr=tensor(raw["object_pointer"],backbone_features.device); score=tensor(raw["object_score"],backbone_features.device)
        return None,None,iou,low,high,ptr,score
    def encode_memory(self,current_vision_feats,feat_sizes,pred_masks_high_res,object_score_logits,is_mask_from_pts):
        pix=current_vision_feats[-1].permute(1,2,0).reshape(1,256,64,64); model=memory[bool(is_mask_from_pts)]
        before=time.perf_counter();raw=model.predict({"pix_feat":pix.detach().float().cpu().numpy(),"mask_logits":pred_masks_high_res.detach().float().cpu().numpy(),"object_score_logits":object_score_logits.detach().float().cpu().numpy(),"mask_mode":np.array([1.0 if is_mask_from_pts else 0.0],np.float32)});stage("memory_point" if is_mask_from_pts else "memory_tracking",time.perf_counter()-before)
        return tensor(raw["memory_features"],pix.device),[tensor(raw["memory_positions"],pix.device)]
    SAM2Base.forward_image=forward_image; SAM2Base._forward_sam_heads=sam_heads; SAM2Base._encode_new_memory=encode_memory; MemoryAttention.forward=attention_forward
    return originals

def compare(original, substituted, report):
    import numpy as np
    from PIL import Image
    a={x["sourceFrameIndex"]:x for x in original["samples"]}; b={x["sourceFrameIndex"]:x for x in substituted["samples"]}
    if a.keys()!=b.keys(): raise RuntimeError("source frame sets differ")
    rows=[]
    for idx in sorted(a):
        x,y=a[idx],b[idx]; empty=x["visible"]!=y["visible"]
        if abs(x["timestamp"]-y["timestamp"])>1e-9: raise RuntimeError("source PTS mismatch")
        if x["visible"] and y["visible"]:
            ma=np.asarray(Image.open(x["rawBinaryMaskPath"]),dtype=bool); mb=np.asarray(Image.open(y["rawBinaryMaskPath"]),dtype=bool); union=(ma|mb).sum(); iou=float((ma&mb).sum()/union) if union else 1.0; centroid=((x["x"]-y["x"])*original["width"])**2+((x["y"]-y["y"])*original["height"])**2; centroid=centroid**.5
        else: iou=None; centroid=None
        rows.append({"sourceFrameIndex":idx,"emptyDisagreement":empty,"maskIoU":iou,"centroidErrorPx":centroid,"objectScoreDifference":abs(x.get("objectScoreLogit",0)-y.get("objectScoreLogit",0))})
    report.update({"frames":rows,"allNonemptyAgreement":not any(x["emptyDisagreement"] for x in rows),"minimumMaskIoU":min((x["maskIoU"] for x in rows if x["maskIoU"] is not None),default=1.0),"maximumCentroidErrorPx":max((x["centroidErrorPx"] for x in rows if x["centroidErrorPx"] is not None),default=0.0)})

def main():
    p=argparse.ArgumentParser(); p.add_argument("--config",type=Path,required=True);p.add_argument("--source",type=Path,required=True);p.add_argument("--checkpoint",type=Path,required=True);p.add_argument("--output-dir",type=Path,required=True);p.add_argument("--packages-root",type=Path,required=True);p.add_argument("--original-control",type=Path);a=p.parse_args()
    config,source,checkpoint,out,root=map(outside,(a.config,a.source,a.checkpoint,a.output_dir,a.packages_root))
    if out.exists(): raise FileExistsError("refusing to overwrite a prior probe output directory")
    out.mkdir(parents=True)
    packages={"image":root/"output-image-memory-corrected4/image/edgetam_image_encoder.mlpackage","trackingMemory":root/"output-image-memory-corrected4/memory/edgetam_memory_encoder_perceiver_sigmoid_tracking.mlpackage","pointMemory":root/"output-image-memory-corrected4/memory/edgetam_memory_encoder_perceiver_binarized_point.mlpackage","attention":root/"output-variable-memory-attention-torch27/edgetam_variable_memory_attention.mlpackage","point":root/"output-sam-heads-fixed-prompt-torch27/edgetam_sam_heads_fixed_prompt.mlpackage","noPoint":root/"output-sam-heads-no-point-fixed-torch27/edgetam_sam_heads_no_point.mlpackage"}
    if not all(x.is_dir() for x in packages.values()): raise RuntimeError("required corrected component package missing")
    started=time.perf_counter(); log_path=out/"stages.jsonl"; stages={}
    def stage(name,elapsed):
        record={"stage":name,"elapsedSeconds":elapsed,"atSeconds":time.perf_counter()-started}; stages[name]=stages.get(name,0.0)+elapsed
        with log_path.open("a") as stream: stream.write(json.dumps(record)+"\n");stream.flush()
    report={"status":"started","codeSHA256":sha(Path(__file__)),"adapterSHA256":sha(ADAPTER),"configurationSHA256":sha(config),"checkpointSHA256":sha(checkpoint),"sourceSHA256":sha(outside(Path(json.loads(config.read_text())["source_path"]))),"componentPackageTreeSHA256":{k:tree_sha(v) for k,v in packages.items()},"coreMLComputeUnits":"ALL","environment":{"python":platform.python_version()},"requestedFrames":32};atomic_json(out/"evidence.json",report)
    originals=None
    try:
        control=outside(a.original_control) if a.original_control else None
        if control:
            candidate=json.loads(control.read_text())
            model=candidate.get("model",{})
            if len(candidate.get("samples",[]))!=32 or model.get("adapterSHA256")!=report["adapterSHA256"] or model.get("configurationSHA256")!=report["configurationSHA256"] or model.get("checkpointSHA256")!=report["checkpointSHA256"] or candidate.get("sourceHash")!="sha256:"+report["sourceSHA256"]: raise RuntimeError("reusable original control provenance does not match current frozen inputs")
            originals=candidate;report["originalControl"]="verified-reused";atomic_json(out/"original.json",candidate)
        else:
            adapter=load_adapter();original_path=out/"original.json";before=time.perf_counter();run_adapter(adapter,config,source,checkpoint,original_path);stage("original_torch_cpu",time.perf_counter()-before);originals=json.loads(original_path.read_text());report["originalControl"]="fresh-cpu"
        adapter=load_adapter();before=time.perf_counter(); originals_methods=install_bridges(source,packages,stage)
        try: run_adapter(adapter,config,source,checkpoint,out/"coreml.json")
        finally:
            from sam2.modeling.sam2_base import SAM2Base
            from sam2.modeling.memory_attention import MemoryAttention
            SAM2Base.forward_image=originals_methods["forward_image"];SAM2Base._forward_sam_heads=originals_methods["sam"];SAM2Base._encode_new_memory=originals_methods["memory"];MemoryAttention.forward=originals_methods["attention"]
        stage("substituted_run_total",time.perf_counter()-before);substituted=json.loads((out/"coreml.json").read_text())
        if len(substituted.get("samples",[]))!=32: raise RuntimeError("substituted run did not emit exactly 32 corresponding source PTS")
        compare(originals,substituted,report);report["passesGate"]=report["allNonemptyAgreement"] and report["minimumMaskIoU"]>=.9 and report["maximumCentroidErrorPx"]<=.5;report["status"]="completed" if report["passesGate"] else "gate-failed"
    except Exception as error:
        report.update({"status":"error","errorType":type(error).__name__,"error":str(error),"traceback":traceback.format_exc()})
    report["stageElapsedSeconds"]=stages;report["elapsedSeconds"]=time.perf_counter()-started;atomic_json(out/"evidence.json",report);print(json.dumps({k:report.get(k) for k in ("status","passesGate","elapsedSeconds")}))
if __name__=="__main__":main()
