param([string]$PreviewPath, [string]$Version='1.0.1')
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$output=Join-Path $repo '.local/avatar-packages'
$model=Join-Path $repo 'apps/mobile_poc/assets/live2d/Mark'
if(!$PreviewPath){$PreviewPath=Join-Path $repo '.local/live2d/evidence/mark-preview.png'}
if(!(Test-Path -LiteralPath $PreviewPath)){throw 'Run package-fixture and collect app_flutter/mark-preview.png first'}
if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Version must have three numeric components'}
New-Item -ItemType Directory -Force $output | Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Linq;
using System.Text.Json;
public static class AvatarCanonicalJson {
  public static byte[] Encode(string json) {
    using var doc=JsonDocument.Parse(json);
    using var stream=new MemoryStream();
    using(var writer=new Utf8JsonWriter(stream)) { Write(writer,doc.RootElement); }
    return stream.ToArray();
  }
  static void Write(Utf8JsonWriter writer,JsonElement value) {
    if(value.ValueKind==JsonValueKind.Object) {
      writer.WriteStartObject();
      foreach(var property in value.EnumerateObject().OrderBy(p=>p.Name,StringComparer.Ordinal)) {
        writer.WritePropertyName(property.Name);Write(writer,property.Value);
      }
      writer.WriteEndObject();
    } else if(value.ValueKind==JsonValueKind.Array) {
      writer.WriteStartArray();foreach(var item in value.EnumerateArray())Write(writer,item);writer.WriteEndArray();
    } else value.WriteTo(writer);
  }
}
'@
function Json-Bytes($value){return ,[AvatarCanonicalJson]::Encode(($value|ConvertTo-Json -Depth 60 -Compress))}
$files=[ordered]@{}
$manifest=[ordered]@{
  format='erciyuan-avatar';formatVersion='0.1';id='mark-demo';version=$Version;name='Mark · 标准联调包'
  renderer='live2d-cubism';runtimeProfile='native-r5-basic-v1';entry='model/character.model3.json';preview='preview.png'
  actions=[ordered]@{
    idle=@{label='自然待机';group='Idle';index=0;playback='loop'}
    wave=@{label='打招呼';group='Actions';index=0;playback='once';returnTo='idle'}
    weight_shift=@{label='换重心';group='Actions';index=1;playback='once';returnTo='idle'}
  };expressions=@{}
}
$files['manifest.json']=Json-Bytes $manifest
$files['preview.png']=[IO.File]::ReadAllBytes($PreviewPath)
$files['model/character.moc3']=[IO.File]::ReadAllBytes((Join-Path $model 'Mark.moc3'))
$files['model/textures/texture_00.png']=[IO.File]::ReadAllBytes((Join-Path $model 'Mark.2048/texture_00.png'))
$files['model/character.physics3.json']=[IO.File]::ReadAllBytes((Join-Path $model 'Mark.physics3.json'))
$descriptor=[ordered]@{Version=3;FileReferences=@{
  Moc='character.moc3';Textures=@('textures/texture_00.png');Physics='character.physics3.json'
  Motions=@{
    Idle=@(@{File='motions/idle.motion3.json';FadeInTime=0.3;FadeOutTime=0.3})
    Actions=@(@{File='motions/wave.motion3.json';FadeInTime=0.3;FadeOutTime=0.3},@{File='motions/weight_shift.motion3.json';FadeInTime=0.3;FadeOutTime=0.3})
  }
};Groups=@(@{Target='Parameter';Name='EyeBlink';Ids=@('ParamEyeLOpen','ParamEyeROpen')})}
$files['model/character.model3.json']=Json-Bytes $descriptor
$ids=(Get-Content (Join-Path $model 'Mark.cdi3.json') -Raw|ConvertFrom-Json).Parameters.Id
function Ease-Keys([double]$time,[double[]]$times,[double[]]$values){
  for($k=1;$k -lt $times.Count;$k++){
    if($time -le $times[$k]){
      $u=($time-$times[$k-1])/($times[$k]-$times[$k-1]);$u=(1-[Math]::Cos([Math]::PI*$u))/2
      return $values[$k-1]*(1-$u)+$values[$k]*$u
    }
  }
  return $values[-1]
}
foreach($action in @('idle','wave','weight_shift')){
  $duration=@{idle=6;wave=3;weight_shift=4}[$action];$frames=$duration*30;$curves=@()
  foreach($id in $ids){
    $segments=[Collections.Generic.List[object]]::new()
    for($frame=0;$frame -le $frames;$frame++){
      $t=$frame/30.0;$v=0.0
      if($id -in @('ParamEyeLOpen','ParamEyeROpen','ParamBrowLY','ParamBrowRY')){$v=1.0}
      if($action -eq 'idle'){
        if($id -eq 'ParamBreath'){$v=0.45*[Math]::Pow([Math]::Sin([Math]::PI*$t/6),2)}
        if($id -eq 'ParamBodyAngleZ'){$v=0.6*[Math]::Sin(2*[Math]::PI*$t/6)}
        if($id -in @('ParamEyeLOpen','ParamEyeROpen')){$v=Ease-Keys $t @(0,2.8,2.9,3.03,3.16,6) @(1,1,0,0,1,1)}
      } elseif($action -eq 'wave'){
        $a=Ease-Keys $t @(0,0.6,1.0,1.35,1.7,2.05,2.4,3) @(0,23,30,19,30,19,26,0)
        if($id -eq 'ParamArmR'){$v=$a}
        if($id -eq 'ParamAngleZ'){$v=-$a/8}
        if($id -eq 'ParamBodyAngleZ'){$v=$a/16}
        if($id -eq 'ParamMouthOpenY'){$v=0.18*[Math]::Sin([Math]::PI*$t/3)}
      } else {
        $a=Ease-Keys $t @(0,1.2,2.4,4) @(0,1,1,0)
        switch($id){
          ParamLeftLeg {$v=-3.0*$a}
          ParamRightLeg {$v=7.0*$a}
          ParamBodyAngleX {$v=4.0*$a}
          ParamBodyAngleZ {$v=-2.5*$a}
          ParamAngleZ {$v=1.5*$a}
          ParamArmL {$v=2*$a}
          ParamArmR {$v=-2*$a}
        }
      }
      if($frame -gt 0){$segments.Add(0)}
      $segments.Add([Math]::Round($t,6));$segments.Add([Math]::Round($v,6))
    }
    $curves+=@{Target='Parameter';Id=$id;Segments=$segments.ToArray()}
  }
  $motion=@{Version=3;Meta=@{Duration=$duration;Fps=30;Loop=($action -eq 'idle');AreBeziersRestricted=$true;CurveCount=$ids.Count;TotalSegmentCount=$ids.Count*$frames;TotalPointCount=$ids.Count*($frames+1);UserDataCount=0;TotalUserDataSize=0};Curves=$curves;UserData=@()}
  $files["model/motions/$action.motion3.json"]=Json-Bytes $motion
}
function Write-Package([string]$name,$entries){
  $target=Join-Path $output $name
  $stream=[IO.File]::Open($target,[IO.FileMode]::Create)
  $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
  try { foreach($key in $entries.Keys){
    $entry=$zip.CreateEntry($key,[IO.Compression.CompressionLevel]::Optimal)
    $entry.LastWriteTime=[DateTimeOffset]::new(2026,11,14,0,0,0,[TimeSpan]::Zero)
    $dest=$entry.Open();try{$bytes=[byte[]]$entries[$key];$dest.Write($bytes,0,$bytes.Length)}finally{$dest.Dispose()}
  }}finally{$zip.Dispose();$stream.Dispose()}
  $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
  [IO.File]::WriteAllText("$target.sha256","$hash  $name`n",$utf8)
  Write-Output "$name $hash"
}
Write-Package "mark-demo-$Version.zip" $files
# Synthetic second package uses the SAME Mark rig, solely for package switching tests.
$alt=[ordered]@{};foreach($k in $files.Keys){$alt[$k]=$files[$k]}
$manifest.id='mark-switch-fixture';$manifest.name='Mark · 切换测试夹具';$alt['manifest.json']=Json-Bytes $manifest
Write-Package 'mark-switch-fixture.zip' $alt
$manifest.id='mark-demo';$manifest.name='Mark · 标准联调包'
foreach($bad in @('missing-texture','bad-index','bad-moc','corrupt-moc','illegal-path','duplicate-json','unknown-parameter','bad-motion','case-collision','version-conflict','broken-texture','large-cover','unknown-field','string-index')){
  $f=[Collections.Generic.Dictionary[string,byte[]]]::new([StringComparer]::Ordinal);foreach($k in $files.Keys){$f[$k]=$files[$k]}
  if($bad -ne 'version-conflict'){
    $m=$utf8.GetString($f['manifest.json'])|ConvertFrom-Json -AsHashtable
    $m.id="invalid-$bad";$f['manifest.json']=Json-Bytes $m
  }
  switch($bad){
    missing-texture {[void]$f.Remove('model/textures/texture_00.png')}
    bad-index {$m=$utf8.GetString($f['manifest.json'])|ConvertFrom-Json -AsHashtable;$m.actions.wave.index=63;$f['manifest.json']=Json-Bytes $m}
    bad-moc {$b=[byte[]]$f['model/character.moc3'].Clone();$b[4]=255;$f['model/character.moc3']=$b}
    corrupt-moc {$f['model/character.moc3']=[byte[]]$f['model/character.moc3'][0..127]}
    illegal-path {$f['../escape.json']=$utf8.GetBytes('{}')}
    duplicate-json {$f['manifest.json']=$utf8.GetBytes('{"format":"x",'+$utf8.GetString($f['manifest.json']).Substring(1))}
    unknown-parameter {$f['model/motions/wave.motion3.json']=$utf8.GetBytes($utf8.GetString($f['model/motions/wave.motion3.json']).Replace('ParamArmR','ParamInventedArm'))}
    bad-motion {$m=$utf8.GetString($f['model/motions/wave.motion3.json'])|ConvertFrom-Json -AsHashtable;$m.Meta.TotalPointCount=1;$f['model/motions/wave.motion3.json']=Json-Bytes $m}
    case-collision {$f['PREVIEW.png']=$f['preview.png']}
    version-conflict {$m=$utf8.GetString($f['manifest.json'])|ConvertFrom-Json -AsHashtable;$m.name='same version changed';$f['manifest.json']=Json-Bytes $m}
    broken-texture {$f['model/textures/texture_00.png']=[byte[]]$f['model/textures/texture_00.png'][0..32]}
    large-cover {$b=[byte[]]$f['preview.png'].Clone();$b[16]=0;$b[17]=0;$b[18]=8;$b[19]=1;$f['preview.png']=$b}
    unknown-field {$m=$utf8.GetString($f['manifest.json'])|ConvertFrom-Json -AsHashtable;$m.unknown='invalid';$f['manifest.json']=Json-Bytes $m}
    string-index {$m=$utf8.GetString($f['manifest.json'])|ConvertFrom-Json -AsHashtable;$m.actions.wave.index='0';$f['manifest.json']=Json-Bytes $m}
  }
  Write-Package "invalid-$bad.zip" $f
}
# Corrupt central/local ZIP metadata to exercise checks before and during inflation.
foreach($bad in @('symlink','declared-size','actual-size','encrypted')){
  $bytes=[IO.File]::ReadAllBytes((Join-Path $output "mark-demo-$Version.zip"))
  $end=$bytes.Length-22;$cd=[BitConverter]::ToUInt32($bytes,$end+16);$local=[BitConverter]::ToUInt32($bytes,$cd+42)
  switch($bad){
    symlink {[BitConverter]::GetBytes([uint32]::Parse('A1FF0000',[Globalization.NumberStyles]::HexNumber)).CopyTo($bytes,$cd+38)}
    declared-size {[BitConverter]::GetBytes([uint32](65*1024*1024)).CopyTo($bytes,$cd+24)}
    actual-size {[BitConverter]::GetBytes([uint32]1).CopyTo($bytes,$cd+24);[BitConverter]::GetBytes([uint32]1).CopyTo($bytes,$local+22)}
    encrypted {$bytes[$cd+8]=$bytes[$cd+8] -bor 1;$bytes[$local+6]=$bytes[$local+6] -bor 1}
  }
  [IO.File]::WriteAllBytes((Join-Path $output "invalid-$bad.zip"),$bytes)
}
