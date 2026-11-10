using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace CoveApp {
 public sealed class VoiceChoice {
  public string Id{get;set;}public string Name{get;set;}public string Gender{get;set;}public string Description{get;set;}
  public override string ToString(){return Name;}
 }
 public sealed class WindowsVoice : IDisposable {
  sealed class Request{public string Text,Id;public int Generation;public TaskCompletionSource<bool> Result;}
  readonly BlockingCollection<Request> requests=new BlockingCollection<Request>();
  readonly Thread worker;int generation;volatile bool stopping;
  public static VoiceChoice[] Voices(){
   var voices=new List<VoiceChoice>();
   foreach(string root in new[]{@"SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens",@"SOFTWARE\Microsoft\Speech\Voices\Tokens"})
   using(var tokens=Registry.LocalMachine.OpenSubKey(root)) {
    if(tokens==null)continue;
    foreach(string id in tokens.GetSubKeyNames())using(var key=tokens.OpenSubKey(id))using(var attrs=key.OpenSubKey("Attributes")) {
     if(attrs==null)continue;string language=attrs.GetValue("Language","").ToString();
     if(Array.IndexOf(language.Split(';'),"416")<0)continue;
     string name=attrs.GetValue("Name",id).ToString(),gender=attrs.GetValue("Gender","").ToString();
     if(root.IndexOf("OneCore",StringComparison.Ordinal)>=0)name+=" (Windows)";
     voices.Add(new VoiceChoice{Id=@"HKEY_LOCAL_MACHINE\"+root+@"\"+id,Name=name,Gender=gender});
    }
   }return voices.ToArray();
  }
  public WindowsVoice(){worker=new Thread(Run);worker.IsBackground=true;worker.SetApartmentState(ApartmentState.STA);worker.Start();}
  static object Invoke(object obj,string name,BindingFlags flags,params object[] args){return obj.GetType().InvokeMember(name,flags,null,obj,args);}
  public Task<bool> Speak(string text,string voiceId){
   if(stopping)throw new ObjectDisposedException("WindowsVoice");
   int current=Interlocked.Increment(ref generation);
   var request=new Request{Text=text,Id=voiceId,Generation=current,Result=new TaskCompletionSource<bool>()};
   requests.Add(request);return request.Result.Task;
  }
  public void Stop(){Interlocked.Increment(ref generation);}
  void Run(){
   object speaker=null;
   try {
    foreach(var request in requests.GetConsumingEnumerable()) {
     if(stopping||request.Generation!=generation){request.Result.TrySetCanceled();continue;}
     object token=null;
     try {
      if(speaker==null)speaker=Activator.CreateInstance(Type.GetTypeFromProgID("SAPI.SpVoice",true));
      token=Activator.CreateInstance(Type.GetTypeFromProgID("SAPI.SpObjectToken",true));
      Invoke(token,"SetId",BindingFlags.InvokeMethod,request.Id,null,false);
      Invoke(speaker,"Voice",BindingFlags.SetProperty,token);
      Invoke(speaker,"Rate",BindingFlags.SetProperty,-1);
      Invoke(speaker,"Volume",BindingFlags.SetProperty,90);
      Invoke(speaker,"Speak",BindingFlags.InvokeMethod,request.Text,1);
      bool finished=false;
      while(!stopping&&request.Generation==generation){if((bool)Invoke(speaker,"WaitUntilDone",BindingFlags.InvokeMethod,40)){finished=true;break;}}
      if(!finished){Invoke(speaker,"Speak",BindingFlags.InvokeMethod,"",3);request.Result.TrySetCanceled();}
      else request.Result.TrySetResult(true);
     }catch{
      request.Result.TrySetException(new Exception("Nao foi possivel usar esta voz brasileira. Escolha outra voz em Ajustes > Voz e teste novamente."));
      if(speaker!=null){try{Marshal.FinalReleaseComObject(speaker);}catch{}speaker=null;}
     }finally{if(token!=null)try{Marshal.FinalReleaseComObject(token);}catch{}}
    }
   }finally{if(speaker!=null)try{Marshal.FinalReleaseComObject(speaker);}catch{}}
  }
  public void Dispose(){stopping=true;Stop();requests.CompleteAdding();worker.Join(1000);}
 }
}
