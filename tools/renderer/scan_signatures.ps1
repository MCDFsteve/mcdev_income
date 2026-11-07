# Read-only check of tools/renderer/native/signatures.h against a running game.
# Run on Windows while the game is open:
#   powershell -ExecutionPolicy Bypass -File tools\renderer\scan_signatures.ps1 [path filter]
# Every signature must report exactly one hit for the Metal adapter to attach.
param([string]$Filter = '*')
Add-Type -TypeDefinition @"
using System; using System.Collections.Generic; using System.Runtime.InteropServices;
public static class Scan {
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint a,bool b,int p);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,IntPtr n,out IntPtr r);
  [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr VirtualQueryEx(IntPtr h,IntPtr a,out Info m,IntPtr l);
  [StructLayout(LayoutKind.Sequential)] struct Info { public IntPtr Base,AllocBase; public uint AllocProtect,Pad0; public IntPtr Size; public uint State,Protect,Type,Pad1; }
  static byte[] image; static bool[] code;
  public static void Load(int pid,long start,int size) {
    IntPtr h=OpenProcess(0x410,false,pid); image=new byte[size]; code=new bool[size];
    long a=start,end=start+size; Info m;
    while(a<end && VirtualQueryEx(h,(IntPtr)a,out m,(IntPtr)Marshal.SizeOf(typeof(Info)))!=IntPtr.Zero) {
      long next=m.Base.ToInt64()+m.Size.ToInt64();
      bool exec=(m.Protect&0xF0)!=0;
      if(m.State==0x1000 && (m.Protect&0x100)==0 && exec) {
        long n=Math.Min(next,end)-a; byte[] t=new byte[n]; IntPtr r;
        if(ReadProcessMemory(h,(IntPtr)a,t,(IntPtr)n,out r)) {
          int offset=(int)(a-start); int got=(int)r.ToInt64();
          Buffer.BlockCopy(t,0,image,offset,got);
          for(int i=0;i<got;i++) code[offset+i]=true;
        }
      }
      a=next;
    }
  }
  public static int[] Find(string pattern) {
    string[] parts=pattern.Split(' '); int n=parts.Length; byte[] v=new byte[n]; bool[] w=new bool[n];
    for(int i=0;i<n;i++){ w[i]=parts[i]=="??"; if(!w[i]) v[i]=Convert.ToByte(parts[i],16); }
    List<int> hits=new List<int>();
    for(int i=0;i<image.Length-n;i++){ if(image[i]!=v[0]||!code[i]) continue; bool ok=true;
      for(int j=1;j<n;j++){ if(!w[j]&&image[i+j]!=v[j]){ok=false;break;} }
      if(ok) hits.Add(i); }
    return hits.ToArray();
  }
  public static int Rel(int at,int end){ return end+BitConverter.ToInt32(image,at); }
  public static uint U32(int rva){ return BitConverter.ToUInt32(image,rva); }
}
"@
$game = Get-Process Minecraft.Windows -ErrorAction SilentlyContinue | Where { $_.Path -like $Filter } | Select -First 1
if (-not $game) { throw 'No running game matches the filter.' }
$module = $game.MainModule
[Scan]::Load($game.Id, $module.BaseAddress.ToInt64(), $module.ModuleMemorySize)
"$($game.Path)"
$header = Get-Content (Join-Path $PSScriptRoot 'native\signatures.h') -Raw
$failed = 0
$found = @{}
foreach ($match in [regex]::Matches($header, '#define SIGNATURE_(\w+) "([^"]+)"')) {
  $name = $match.Groups[1].Value
  if ($name -eq 'CAPS_GETTER') { continue }
  $hits = [Scan]::Find($match.Groups[2].Value)
  "{0,-18} {1} hit(s) {2}" -f $name, $hits.Count, (($hits | Select -First 4 | ForEach { '0x' + $_.ToString('x8') }) -join ' ')
  if ($hits.Count -ne 1) { $failed++ } else { $found[$name] = $hits[0] }
}
if ($found.DEFERRED) {
  $getter = [Scan]::Rel($found.DEFERRED + 7, $found.DEFERRED + 11)
  $caps = [Scan]::Find('48 8d 05 ?? ?? ?? ?? c3') -contains $getter
  "caps getter        0x$($getter.ToString('x8')) $(if ($caps) { 'ok' } else { 'MISMATCH' })"
  if (-not $caps) { $failed++ }
}
if ($found.STRUCTURED_CREATE -and $found.STRUCTURED_UPDATE) {
  $table = [Scan]::U32($found.STRUCTURED_CREATE + 17)
  $same = $table -eq [Scan]::U32($found.STRUCTURED_UPDATE + 10)
  "structured table   0x$($table.ToString('x')) $(if ($same) { 'ok' } else { 'MISMATCH' })"
  if (-not $same) { $failed++ }
}
if ($failed) { "FAILED: $failed"; exit 1 }
'ALL SIGNATURES RESOLVED'
