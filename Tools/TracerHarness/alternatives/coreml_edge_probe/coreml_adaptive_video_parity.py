#!/usr/bin/env python3
"""CPU-Torch versus Core ML ALL parity for frozen adaptive EdgeTAM runs.

The runner records strict PNG-byte parity separately from the predeclared
numerical binary-mask gate.  ``--rescore-root`` is offline-only: it never
invokes a model and never replaces an executed run's evidence.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, platform, sys, tempfile, time, traceback
from pathlib import Path
from PIL import Image

REPO=Path(__file__).resolve().parents[4]
ADAPTER=REPO/'Tools/TracerHarness/alternatives/edgetam_adaptive_adapter.py'
BRIDGE=REPO/'Tools/TracerHarness/alternatives/coreml_edge_probe/coreml_video_component_parity.py'

def external(path):
 p=Path(path).expanduser().resolve()
 if p==REPO or REPO in p.parents: raise ValueError('private paths must be outside repository')
 return p

def sha(path):
 h=hashlib.sha256()
 with Path(path).open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''): h.update(b)
 return h.hexdigest()

def tree(path):
 h=hashlib.sha256()
 for p in sorted(x for x in Path(path).rglob('*') if x.is_file()): h.update(p.relative_to(path).as_posix().encode()+b'\0'+sha(p).encode()+b'\n')
 return h.hexdigest()

def atomic(path,value,replace=False):
 if path.exists() and not replace: raise FileExistsError(f'refuse overwrite: {path}')
 t=path.with_suffix(path.suffix+'.tmp')
 t.write_text(json.dumps(value,indent=2)+'\n')
 os.replace(t,path)

def module(path,name):
 if str(path.parent) not in sys.path: sys.path.insert(0,str(path.parent))
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m

def invoke(adapter,config,source,checkpoint,output):
 old=sys.argv
 try:
  sys.argv=[str(ADAPTER),'--config',str(config),'--edgetam-root',str(source),'--checkpoint',str(checkpoint),'--output',str(output),'--device','cpu'];adapter.run()
 finally: sys.argv=old

def package_map(root):
 return {'image':root/'output-image-memory-corrected4/image/edgetam_image_encoder.mlpackage','trackingMemory':root/'output-image-memory-corrected4/memory/edgetam_memory_encoder_perceiver_sigmoid_tracking.mlpackage','pointMemory':root/'output-image-memory-corrected4/memory/edgetam_memory_encoder_perceiver_binarized_point.mlpackage','attention':root/'output-variable-memory-attention-torch27/edgetam_variable_memory_attention.mlpackage','point':root/'output-sam-heads-fixed-prompt-torch27/edgetam_sam_heads_fixed_prompt.mlpackage','noPoint':root/'output-sam-heads-no-point-fixed-torch27/edgetam_sam_heads_no_point.mlpackage'}

def comparable_transition(item): return {k:v for k,v in item.items() if k not in ('canonicalMaskPath','newSeedMask')}

def binary_mask_metrics(left_path,right_path):
 """Compare foreground bits, deliberately independent of PNG serialisation."""
 with Image.open(left_path) as left_image, Image.open(right_path) as right_image:
  if left_image.size!=right_image.size:
   return {'sameShape':False,'binaryIdentical':False,'iou':0.0,'xorPixels':None,'controlForegroundPixels':None,'coreMLForegroundPixels':None}
  left=[pixel!=0 for pixel in left_image.convert('L').getdata()]
  right=[pixel!=0 for pixel in right_image.convert('L').getdata()]
 intersection=sum(a and b for a,b in zip(left,right));union=sum(a or b for a,b in zip(left,right))
 return {'sameShape':True,'binaryIdentical':left==right,'iou':1.0 if union==0 else intersection/union,'xorPixels':sum(a!=b for a,b in zip(left,right)),'controlForegroundPixels':sum(left),'coreMLForegroundPixels':sum(right)}

def compare(control,coreml):
 diffs=[];a=control['samples'];b=coreml['samples'];rows=[]
 if len(a)!=len(b): diffs.append({'kind':'sampleCount','control':len(a),'coreml':len(b)})
 for left,right in zip(a,b):
  frame=left.get('sourceFrameIndex')
  for key in ('timestamp','sourceFrameIndex','visible','processingStatus','direction'):
   if left.get(key)!=right.get(key): diffs.append({'kind':'sampleField','frame':frame,'field':key,'control':left.get(key),'coreml':right.get(key)})
  left_path=left.get('rawBinaryMaskPath');right_path=right.get('rawBinaryMaskPath')
  required=bool(left.get('visible') or right.get('visible') or left_path or right_path
                or left.get('processingStatus') in ('observed_mask','empty_mask')
                or right.get('processingStatus') in ('observed_mask','empty_mask'))
  available=bool(left_path and right_path and Path(left_path).is_file() and Path(right_path).is_file())
  metrics=None;byte_identical=None
  if required and not available:
   diffs.append({'kind':'requiredMaskMissing','frame':frame,'controlHasMask':bool(left_path and Path(left_path).is_file()),'coreMLHasMask':bool(right_path and Path(right_path).is_file())})
  elif left_path or right_path:
   if not available:
    diffs.append({'kind':'maskPresence','frame':frame,'controlHasMask':bool(left_path and Path(left_path).is_file()),'coreMLHasMask':bool(right_path and Path(right_path).is_file())})
   else:
    metrics=binary_mask_metrics(left_path,right_path)
    byte_identical=sha(left_path)==sha(right_path)
    if not byte_identical: diffs.append({'kind':'maskBytes','frame':frame,'controlMaskFile':Path(left_path).name,'coreMLMaskFile':Path(right_path).name})
    if not metrics['binaryIdentical']: diffs.append({'kind':'maskBinary','frame':frame,'iou':metrics['iou'],'xorPixels':metrics['xorPixels']})
  if left.get('visible') and right.get('visible'):
   dx=(left['x']-right['x'])*control['width'];dy=(left['y']-right['y'])*control['height'];centroid=(dx*dx+dy*dy)**.5
  else: centroid=None
  rows.append({'sourceFrameIndex':frame,'timestamp':left.get('timestamp'),'maskByteIdentical':byte_identical,'binaryMaskIdentical':metrics['binaryIdentical'] if metrics else None,'maskIoU':metrics['iou'] if metrics else None,'maskXorPixels':metrics['xorPixels'] if metrics else None,'centroidErrorPx':centroid,'emptyDisagreement':left.get('visible')!=right.get('visible'),'objectScoreDifference':abs(left.get('objectScoreLogit',0)-right.get('objectScoreLogit',0))})
 for key in ('automaticReseedCount','directionTermination','maximumSourceTimeGapSeconds','gapRecoveryCount'):
  if control.get(key)!=coreml.get(key): diffs.append({'kind':'runField','field':key,'control':control.get(key),'coreml':coreml.get(key)})
 for key in ('segments','automaticTransitions'):
  ca=[comparable_transition(x) for x in control.get(key,[])];cb=[comparable_transition(x) for x in coreml.get(key,[])]
  if ca!=cb: diffs.append({'kind':'transitionOrAnchor','field':key,'control':ca,'coreml':cb})
 return rows,diffs

def score(control,coreml):
 rows,diffs=compare(control,coreml)
 kinds=[d['kind'] for d in diffs]
 min_iou=min((r['maskIoU'] for r in rows if r['maskIoU'] is not None),default=1.0)
 max_centroid=max((r['centroidErrorPx'] for r in rows if r['centroidErrorPx'] is not None),default=0.0)
 same_sample_fields=not any(k in ('sampleCount','sampleField') for k in kinds)
 same_nonempty=not any(r['emptyDisagreement'] for r in rows)
 same_resets=not any(d.get('field')=='automaticReseedCount' for d in diffs if d['kind']=='runField')
 same_termination=not any(k in ('transitionOrAnchor','runField') for k in kinds)
 masks_present=not any(k=='requiredMaskMissing' for k in kinds)
 numerical=all((same_sample_fields,same_nonempty,same_resets,same_termination,masks_present,min_iou>=.9,max_centroid<=.5))
 exact=not any(k in ('maskBytes','maskPresence','requiredMaskMissing') for k in kinds)
 return {'frames':rows,'differences':diffs,'controlNonempty':len(control['frames']),'coremlNonempty':len(coreml['frames']),'controlResets':control['automaticReseedCount'],'coremlResets':coreml['automaticReseedCount'],'minimumMaskIoU':min_iou,'maximumCentroidErrorPx':max_centroid,'samePTSAndStatuses':same_sample_fields,'sameNonempty':same_nonempty,'sameResets':same_resets,'sameTerminationsAndTransitions':same_termination,'masksPresent':masks_present,'numericalPass':numerical,'exactBytePass':exact,'passesGate':numerical}

def synthetic_check():
 with tempfile.TemporaryDirectory(prefix='ronde-adaptive-mask-check-') as directory:
  root=Path(directory);pixels=[0,255,0,255]
  first=root/'same-uncompressed.png';second=root/'same-compressed.png';changed=root/'one-pixel-difference.png'
  image=Image.new('L',(2,2));image.putdata(pixels);image.save(first,format='PNG',compress_level=0);image.save(second,format='PNG',compress_level=9)
  changed_image=Image.new('L',(2,2));changed_image.putdata([255,255,0,255]);changed_image.save(changed,format='PNG',compress_level=9)
  same=binary_mask_metrics(first,second);different=binary_mask_metrics(first,changed)
  assert sha(first)!=sha(second) and same['binaryIdentical'] and same['iou']==1.0
  assert not different['binaryIdentical'] and different['xorPixels']==1 and different['iou']==2/3
  return {'samePixelsDifferentPNGBytes':{'byteIdentical':False,'binaryIdentical':same['binaryIdentical'],'iou':same['iou']},'onePixelDifference':{'binaryIdentical':different['binaryIdentical'],'xorPixels':different['xorPixels'],'iou':different['iou']}}

def run_clip(config,source,checkpoint,packages_root,out):
 if out.exists(): raise FileExistsError('refuse overwrite')
 out.mkdir(parents=True);cfg=json.loads(config.read_text());packages=package_map(packages_root)
 if cfg.get('source_time_gap_seconds')!=.20: raise ValueError('only frozen .20s gap config supported')
 if not all(p.is_dir() for p in packages.values()): raise RuntimeError('component package missing')
 report={'status':'started','configSHA256':sha(config),'sourceSHA256':sha(external(cfg['source_path'])),'cacheSHA256':sha(external(cfg['frame_cache_manifest'])),'avPTSManifestSHA256':sha(external(cfg['avfoundation_frame_manifest'])),'checkpointSHA256':sha(checkpoint),'adaptiveAdapterSHA256':sha(ADAPTER),'bridgeSHA256':sha(BRIDGE),'packageTreeSHA256':{key:tree(value) for key,value in packages.items()},'coreMLComputeUnits':'ALL','environment':{'python':platform.python_version(),'platform':platform.platform()}};atomic(out/'evidence.json',report)
 started=time.perf_counter();stages={};log=out/'stages.jsonl'
 def stage(name,elapsed):
  stages[name]=stages.get(name,0)+elapsed
  with log.open('a') as f: f.write(json.dumps({'stage':name,'elapsedSeconds':elapsed,'atSeconds':time.perf_counter()-started})+'\n');f.flush()
 try:
  adapter=module(ADAPTER,'adaptive_control');before=time.perf_counter();invoke(adapter,config,source,checkpoint,out/'original-cpu.json');stage('original_cpu',time.perf_counter()-before)
  bridge=module(BRIDGE,'bridge_factory');before=time.perf_counter();originals=bridge.install_bridges(source,packages,stage)
  try: invoke(module(ADAPTER,'adaptive_coreml'),config,source,checkpoint,out/'coreml-all.json')
  finally:
   from sam2.modeling.sam2_base import SAM2Base
   from sam2.modeling.memory_attention import MemoryAttention
   SAM2Base.forward_image=originals['forward_image'];SAM2Base._forward_sam_heads=originals['sam'];SAM2Base._encode_new_memory=originals['memory'];MemoryAttention.forward=originals['attention']
  stage('coreml_substituted',time.perf_counter()-before)
  report.update(score(json.loads((out/'original-cpu.json').read_text()),json.loads((out/'coreml-all.json').read_text())))
  report['status']='completed' if report['numericalPass'] else 'gate-failed'
 except Exception as error: report.update({'status':'error','errorType':type(error).__name__,'error':str(error),'traceback':traceback.format_exc()})
 report['stageElapsedSeconds']=stages;report['elapsedSeconds']=time.perf_counter()-started;atomic(out/'evidence.json',report,replace=True);return report

def rescore(root):
 root=external(root);snapshot=root/'provenance/coreml_adaptive_video_parity.executed-2026-09-19.py'
 if not snapshot.is_file(): raise FileNotFoundError('missing executed scorer snapshot')
 results={'schemaVersion':1,'kind':'offline-adaptive-parity-rescore','rescoreScorerSHA256':sha(Path(__file__)),'executedScorerSnapshotSHA256':sha(snapshot),'syntheticMaskCheck':synthetic_check(),'clips':{}}
 for label in ('daylight','night'):
  directory=root/label;evidence=directory/'evidence.json';control=directory/'original-cpu.json';coreml=directory/'coreml-all.json'
  if not all(path.is_file() for path in (evidence,control,coreml)): raise FileNotFoundError(f'missing saved run for {label}')
  report=score(json.loads(control.read_text()),json.loads(coreml.read_text()))
  report.update({'originalEvidenceSHA256':sha(evidence),'controlRunSHA256':sha(control),'coreMLRunSHA256':sha(coreml),'originalEvidenceStatus':json.loads(evidence.read_text()).get('status')})
  mismatch=[row for row in report['frames'] if row['maskByteIdentical'] is False or row['binaryMaskIdentical'] is False]
  report['maskMismatches']=mismatch
  results['clips'][label]=report
 atomic(root/'offline-numerical-rescore.json',results)
 return results

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--rescore-root',type=Path)
 parser.add_argument('--source',type=Path);parser.add_argument('--checkpoint',type=Path);parser.add_argument('--packages-root',type=Path);parser.add_argument('--day-config',type=Path);parser.add_argument('--night-config',type=Path);parser.add_argument('--output-root',type=Path);args=parser.parse_args()
 if args.rescore_root:
  if any((args.source,args.checkpoint,args.packages_root,args.day_config,args.night_config,args.output_root)): parser.error('--rescore-root is offline-only')
  results=rescore(args.rescore_root);print(json.dumps({label:{'numericalPass':item['numericalPass'],'exactBytePass':item['exactBytePass']} for label,item in results['clips'].items()}));return
 required=(args.source,args.checkpoint,args.packages_root,args.day_config,args.night_config,args.output_root)
 if not all(required): parser.error('run mode requires source, checkpoint, packages root, both configs and output root')
 source,checkpoint,root,day,night,out=map(external,required);out.mkdir(parents=True,exist_ok=False);results={}
 for label,config in (('daylight',day),('night',night)):
  results[label]=run_clip(config,source,checkpoint,root,out/label)
  if results[label]['status']!='completed': break
 atomic(out/'summary.json',results);print(json.dumps({key:value['status'] for key,value in results.items()}))
if __name__=='__main__': main()
