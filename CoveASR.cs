using System;
using System.IO;
using System.Diagnostics;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace CoveApp {
 public sealed class CoveTranscription : IDisposable {
  readonly string root;readonly object serial=new object(),processLock=new object();
  Process child;int generation;volatile bool stopping;
  public CoveTranscription(string folder){root=folder;}
  public bool Installed{get{return File.Exists(Path.Combine(root,@"assets\asr\ready.txt"))&&File.Exists(Path.Combine(root,@"assets\asr\small\model.bin"))&&File.Exists(Path.Combine(root,@"assets\neural\python\python.exe"));}}
  static string Quote(string s){return "\""+s.Replace("\"","\\\"")+"\"";}
  public Task<string> Transcribe(byte[] pcm,string hotwords){
   if(stopping)throw new ObjectDisposedException("CoveTranscription");
   int current=generation;
   return Task.Run(()=>Run(pcm,hotwords,current));
  }
  string Run(byte[] pcm,string hotwords,int current){
   lock(serial){
    Check(current);if(!Installed)throw new Exception("A escuta precisa ainda nao foi preparada. Execute Preparar-Escuta.cmd.");
    Process process;
    lock(processLock){
     Check(current);
     if(child==null||child.HasExited){
      if(child!=null)child.Dispose();
      var start=new ProcessStartInfo(Path.Combine(root,@"assets\neural\python\python.exe"),"-u "+Quote(Path.Combine(root,"cove_asr.py"))+" --model "+Quote(Path.Combine(root,@"assets\asr\small"))){UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,WorkingDirectory=root};
      start.EnvironmentVariables["PYTHONIOENCODING"]="utf-8";
      child=new Process{StartInfo=start};child.ErrorDataReceived+=(s,e)=>{};
      if(!child.Start())throw new Exception("Nao foi possivel iniciar a transcricao local.");child.BeginErrorReadLine();
     }process=child;
    }
    try{
     var json=new JavaScriptSerializer{MaxJsonLength=4000000};
     var request=new System.Collections.Generic.Dictionary<string,object>{{"pcm",Convert.ToBase64String(pcm)},{"hotwords",hotwords}};
     byte[] message=Encoding.UTF8.GetBytes(json.Serialize(request)+"\n");
     process.StandardInput.BaseStream.Write(message,0,message.Length);process.StandardInput.BaseStream.Flush();
     var read=process.StandardOutput.ReadLineAsync();DateTime deadline=DateTime.UtcNow.AddSeconds(90);
     while(!read.Wait(40)){Check(current);if(DateTime.UtcNow>deadline)throw new Exception("A transcricao demorou demais. Tente uma fala mais curta.");}
     Check(current);string response=read.GetAwaiter().GetResult();
     if(response==null)throw new Exception("O reconhecedor encerrou inesperadamente. Reinicie o Cove.");
     return response;
    }catch{Check(current);Kill();throw;}
   }
  }
  void Check(int current){if(stopping||generation!=current)throw new OperationCanceledException("Transcricao interrompida.");}
  void Kill(){lock(processLock){if(child!=null){try{if(!child.HasExited)child.Kill();}catch{}try{child.Dispose();}catch{}child=null;}}}
  public void Stop(){Interlocked.Increment(ref generation);if(!Monitor.TryEnter(serial))Kill();else Monitor.Exit(serial);}
  public void Dispose(){stopping=true;Stop();Kill();}
 }
 public sealed class UtteranceBuffer {
  readonly MemoryStream buffer=new MemoryStream();readonly System.Collections.Generic.Queue<byte[]> lead=new System.Collections.Generic.Queue<byte[]>();
  int leadBytes,voicedBytes,silenceBytes;bool started,sent;
  public void Reset(){buffer.SetLength(0);buffer.Position=0;lead.Clear();leadBytes=voicedBytes=silenceBytes=0;started=sent=false;}
  void AddLead(byte[] pcm){lead.Enqueue(pcm);leadBytes+=pcm.Length;while(leadBytes>16000&&lead.Count>1)leadBytes-=lead.Dequeue().Length;}
  public void Seed(byte[] pcm){if(!started)AddLead(pcm);}
  public byte[] Push(byte[] pcm,bool voiced){
   if(sent)return null;
   if(!started){
    AddLead(pcm);voicedBytes=voiced?voicedBytes+pcm.Length:0;
    if(voicedBytes<3840)return null;
    started=true;foreach(byte[] b in lead)buffer.Write(b,0,b.Length);lead.Clear();leadBytes=0;
   }else buffer.Write(pcm,0,pcm.Length);
   silenceBytes=voiced?0:silenceBytes+pcm.Length;
   if(silenceBytes>=35200||buffer.Length>=960000){sent=true;return buffer.ToArray();}
   return null;
  }
 }
}
