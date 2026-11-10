using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Media;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace CoveApp {
 public sealed class CoveSpeech : IDisposable {
  readonly WindowsVoice windows=new WindowsVoice();
  readonly string root,assets;
  readonly object processLock=new object(),serial=new object();
  Process child;SoundPlayer player;int generation;volatile bool stopping;
  public CoveSpeech(string folder){root=folder;assets=Path.Combine(root,@"assets\neural");}
  public static VoiceChoice[] Voices(){
   var result=new List<VoiceChoice>{
    new VoiceChoice{Id="kokoro:serena",Name="Serena - feminina calma",Gender="Female",Description="Voz feminina brasileira, suave, pausada e controlada."},
    new VoiceChoice{Id="kokoro:atlas",Name="Atlas - assistente formal",Gender="Male",Description="Voz masculina brasileira, serena e formal, com ritmo de assistente pessoal."}
   };
   foreach(var voice in WindowsVoice.Voices()){voice.Description="Voz sintetizada do Windows.";result.Add(voice);}return result.ToArray();
  }
  public bool Installed {get{return File.Exists(Path.Combine(assets,"ready.txt"))&&File.Exists(Path.Combine(assets,@"python\python.exe"))&&File.Exists(Path.Combine(assets,"kokoro-v1.0.onnx"))&&File.Exists(Path.Combine(assets,"voices-v1.0.bin"));}}
  static string Quote(string value){return "\""+value.Replace("\"","\\\"")+"\"";}
  public Task<bool> Speak(string text,string id){
   if(stopping)throw new ObjectDisposedException("CoveSpeech");
   Stop();
   if(!id.StartsWith("kokoro:",StringComparison.Ordinal))return windows.Speak(text,id);
   string preset=id.Substring(7);
   if(preset!="serena"&&preset!="atlas")throw new ArgumentException("Perfil de voz desconhecido.");
   int current=generation;
   return Task.Run(()=>GenerateAndPlay(text,preset,current));
  }
  bool GenerateAndPlay(string text,string preset,int current){
   lock(serial){
    CheckGeneration(current);
    if(!Installed)throw new Exception("Prepare as novas vozes em Ajustes > Preparar Serena e Atlas. O download e feito uma unica vez.");
    Process process;
    lock(processLock){
     CheckGeneration(current);
     if(child==null||child.HasExited){
      if(child!=null){child.Dispose();child=null;}
      var start=new ProcessStartInfo(Path.Combine(assets,@"python\python.exe"),"-u "+Quote(Path.Combine(root,"cove_neural.py"))+" --assets "+Quote(assets)){
       UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=root,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8
      };
      start.EnvironmentVariables["PYTHONIOENCODING"]="utf-8";
      child=new Process{StartInfo=start};child.ErrorDataReceived+=(s,e)=>{};
      if(!child.Start())throw new Exception("Nao foi possivel iniciar o mecanismo de voz local.");
      child.StandardInput.AutoFlush=true;child.BeginErrorReadLine();
     }process=child;
    }
    try{
     var json=new JavaScriptSerializer{MaxJsonLength=20000000};
     // JSON is sent through a pipe, never interpolated into a shell command.
     byte[] input=Encoding.UTF8.GetBytes(json.Serialize(new{text=text,preset=preset})+"\n");
     process.StandardInput.BaseStream.Write(input,0,input.Length);process.StandardInput.BaseStream.Flush();
     var read=process.StandardOutput.ReadLineAsync();
     DateTime deadline=DateTime.UtcNow.AddSeconds(120);
     while(!read.Wait(40)){CheckGeneration(current);if(DateTime.UtcNow>deadline)throw new Exception("A geracao da voz demorou demais. Tente uma resposta mais curta.");}
     CheckGeneration(current);
     string response=read.GetAwaiter().GetResult();
     if(response==null)throw new Exception("O mecanismo de voz encerrou. Execute Preparar-Vozes.cmd para conferir a instalacao.");
     byte[] wav=DecodeAudio(response);
     using(var audio=new MemoryStream(wav))using(var sound=new SoundPlayer(audio)){
      lock(processLock){CheckGeneration(current);player=sound;}
      try{sound.Load();CheckGeneration(current);sound.PlaySync();CheckGeneration(current);}
      finally{lock(processLock){if(player==sound)player=null;}}
     }
     return true;
    }catch(OperationCanceledException){throw;}
     catch{CheckGeneration(current);KillChild();throw;}
   }
  }
  public static byte[] DecodeAudio(string response){
   var data=new JavaScriptSerializer{MaxJsonLength=20000000}.DeserializeObject(response) as Dictionary<string,object>;
   if(data==null||data.ContainsKey("error"))throw new Exception("A voz natural nao conseguiu gerar o audio. Execute Preparar-Vozes.cmd novamente.");
   object encoded;if(!data.TryGetValue("audio",out encoded)||!(encoded is string))throw new Exception("O mecanismo de voz retornou uma resposta invalida.");
   var bytes=Convert.FromBase64String((string)encoded);
   if(bytes.Length<44||Encoding.ASCII.GetString(bytes,0,4)!="RIFF"||Encoding.ASCII.GetString(bytes,8,4)!="WAVE")throw new Exception("O audio gerado nao e um WAV valido.");
   return bytes;
  }
  void CheckGeneration(int current){if(stopping||current!=generation)throw new OperationCanceledException("Fala interrompida.");}
  void KillChild(){lock(processLock){if(child!=null){try{if(!child.HasExited)child.Kill();}catch{}try{child.Dispose();}catch{}child=null;}}}
  public void Stop(){
   Interlocked.Increment(ref generation);windows.Stop();
   lock(processLock){if(player!=null){try{player.Stop();}catch{}}}
   // Cancel an active synthesis, but retain an idle loaded model between replies.
   if(!Monitor.TryEnter(serial)){KillChild();}else{Monitor.Exit(serial);}
  }
  public void Dispose(){stopping=true;Stop();KillChild();windows.Dispose();}
 }
}
