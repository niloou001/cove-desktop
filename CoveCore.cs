using System;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Web.Script.Serialization;

namespace CoveApp {
 public sealed class Listener : IDisposable {
  [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct Caps {
   public ushort manufacturer,product;public uint version;
   [MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)] public string name;
   public uint formats;public ushort channels,reserved;
  }
  public sealed class DeviceInfo {public int Id{get;set;}public string Name{get;set;}public override string ToString(){return Name;}}
  [DllImport("winmm.dll")] static extern uint waveInGetNumDevs();
  [DllImport("winmm.dll",CharSet=CharSet.Unicode,EntryPoint="waveInGetDevCapsW")] static extern uint waveInGetDevCaps(UIntPtr id,out Caps caps,uint size);
  public static DeviceInfo[] Devices(){var devices=new List<DeviceInfo>();devices.Add(new DeviceInfo{Id=-1,Name="Microfone padrao do Windows"});for(uint i=0;i<waveInGetNumDevs();i++){Caps c;if(waveInGetDevCaps(new UIntPtr(i),out c,(uint)Marshal.SizeOf(typeof(Caps)))==0)devices.Add(new DeviceInfo{Id=(int)i,Name=c.name});}return devices.ToArray();}
  [StructLayout(LayoutKind.Sequential)] struct Format {
   public ushort tag,channels; public uint rate,bytes; public ushort align,bits,extra;
  }
  [StructLayout(LayoutKind.Sequential)] struct Header {
   public IntPtr data; public uint size,recorded; public UIntPtr user;
   public uint flags,loops; public IntPtr next; public UIntPtr reserved;
  }
  [DllImport("winmm.dll")] static extern uint waveInOpen(out IntPtr h, uint device, ref Format f, IntPtr cb, IntPtr user, uint flags);
  [DllImport("winmm.dll")] static extern uint waveInPrepareHeader(IntPtr h,IntPtr b,uint size);
  [DllImport("winmm.dll")] static extern uint waveInAddBuffer(IntPtr h,IntPtr b,uint size);
  [DllImport("winmm.dll")] static extern uint waveInStart(IntPtr h);
  [DllImport("winmm.dll")] static extern uint waveInReset(IntPtr h);
  [DllImport("winmm.dll")] static extern uint waveInUnprepareHeader(IntPtr h,IntPtr b,uint size);
  [DllImport("winmm.dll")] static extern uint waveInClose(IntPtr h);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool SetDllDirectory(string path);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern void vosk_set_log_level(int level);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern IntPtr vosk_model_new(byte[] path);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern void vosk_model_free(IntPtr model);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern IntPtr vosk_recognizer_new(IntPtr model,float rate);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern IntPtr vosk_recognizer_new_grm(IntPtr model,float rate,byte[] grammar);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern void vosk_recognizer_free(IntPtr r);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern void vosk_recognizer_reset(IntPtr r);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern void vosk_recognizer_set_words(IntPtr r,int enabled);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern int vosk_recognizer_accept_waveform(IntPtr r,byte[] data,int length);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern IntPtr vosk_recognizer_result(IntPtr r);
  [DllImport("libvosk",CallingConvention=CallingConvention.Cdecl)] static extern IntPtr vosk_recognizer_partial_result(IntPtr r);
  public readonly ConcurrentQueue<string> Events = new ConcurrentQueue<string>();
  public readonly ConcurrentQueue<byte[]> Audio = new ConcurrentQueue<byte[]>();
  public volatile bool UseNeural;
  public volatile bool Paused;
  public volatile bool ListeningMode;
  public volatile bool ReplayWakeAudio;
  public volatile bool Ready;
  public volatile string WakeName="Cove";
  public static string NormalizeWake(string value){var text=new StringBuilder();foreach(char c in (value??"").Normalize(NormalizationForm.FormD)){if(System.Globalization.CharUnicodeInfo.GetUnicodeCategory(c)==System.Globalization.UnicodeCategory.NonSpacingMark)continue;text.Append(Char.IsLetterOrDigit(c)?Char.ToLowerInvariant(c):' ');}return System.Text.RegularExpressions.Regex.Replace(text.ToString(),@"\s+"," ").Trim();}
  public static string[] WakeAliases(string name){
   string normal=NormalizeWake(name);if(normal=="cove"||normal.Length==0)return new[]{"couve","cove","couvi"};
   if(NormalizeWake((name??"").Replace(".",""))=="jarvis")return new[]{"jarvis","jarbas"};
   string compact=NormalizeWake((name??"").Replace(".","").Replace("'",""));return compact==normal?new[]{normal}:new[]{normal,compact};
  }
  public static bool WakeMatches(string text,string name){string words=" "+NormalizeWake(text)+" ";foreach(string alias in WakeAliases(name))if(words.Contains(" "+alias+" "))return true;return false;}
  static bool WakeJsonMatches(string json,string name){var obj=new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string,object>;object value;if(obj==null)return false;if(obj.TryGetValue("text",out value)||obj.TryGetValue("partial",out value))return WakeMatches(Convert.ToString(value),name);return false;}
  static IntPtr NewWakeRecognizer(IntPtr model,string name){var phrases=new List<string>(WakeAliases(name));phrases.Add("[unk]");return vosk_recognizer_new_grm(model,16000,Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(phrases)+"\0"));}
  public volatile float Level;
  volatile bool stopping;
  Thread worker;
  readonly int deviceId;
  static void Check(uint code) { if(code!=0) throw new Exception("Microfone indisponivel (codigo " + code + "). Confira o microfone padrao e sua permissao nas Configuracoes do Windows."); }
  static string Utf8(IntPtr p) { if(p==IntPtr.Zero) return "{}"; int n=0; while(Marshal.ReadByte(p,n)!=0)n++; byte[] b=new byte[n]; Marshal.Copy(p,b,0,n);return Encoding.UTF8.GetString(b); }
  public Listener(string nativePath,string modelPath) : this(nativePath,modelPath,-1) {}
  public Listener(string nativePath,string modelPath,int selectedDevice) : this(nativePath,modelPath,selectedDevice,"Cove") {}
  public Listener(string nativePath,string modelPath,int selectedDevice,string wakeName) {
   WakeName=wakeName;
   deviceId=selectedDevice;
   SetDllDirectory(nativePath);
   worker=new Thread(()=>Run(modelPath)); worker.IsBackground=true; worker.Start();
  }
  void Run(string modelPath) {
   IntPtr model=IntPtr.Zero,recognizer=IntPtr.Zero,wake=IntPtr.Zero,mic=IntPtr.Zero;
   var headers=new List<IntPtr>(); var buffers=new List<IntPtr>();
   uint hs=(uint)Marshal.SizeOf(typeof(Header)); bool previousPaused=false,previousMode=false,previousNeural=false,wakeSent=false;
   try {
    vosk_set_log_level(-1);
    model=vosk_model_new(Encoding.UTF8.GetBytes(modelPath+"\0"));
    if(model==IntPtr.Zero) throw new Exception("Modelo de fala nao carregou. Execute Preparar-Cove.cmd novamente.");
    recognizer=vosk_recognizer_new(model,16000);
    if(recognizer==IntPtr.Zero)throw new Exception("Nao foi possivel iniciar o reconhecimento local.");
    vosk_recognizer_set_words(recognizer,1);
    string activeWakeName=WakeName;wake=NewWakeRecognizer(model,activeWakeName);
    if(wake==IntPtr.Zero)throw new Exception("Nao foi possivel iniciar a escuta do nome Cove.");
    int inputRate=16000,inputChannels=1;uint openCode=1;
    foreach(int rate in new[]{16000,48000,44100}) {
     foreach(int channels in new[]{1,2}) {
      var f=new Format{tag=1,channels=(ushort)channels,rate=(uint)rate,bytes=(uint)(rate*channels*2),align=(ushort)(channels*2),bits=16,extra=0};
      openCode=waveInOpen(out mic,unchecked((uint)deviceId),ref f,IntPtr.Zero,IntPtr.Zero,0);
      if(openCode==0){inputRate=rate;inputChannels=channels;break;}
     }if(openCode==0)break;
    }
    Check(openCode);
    var converter=new PcmConverter(inputRate,inputChannels);
    int bufferSize=inputRate*inputChannels*2/10;
    for(int i=0;i<8;i++) {
     IntPtr b=Marshal.AllocHGlobal(bufferSize); buffers.Add(b);
     IntPtr h=Marshal.AllocHGlobal((int)hs); headers.Add(h);
     Marshal.StructureToPtr(new Header{data=b,size=(uint)bufferSize},h,false);
     Check(waveInPrepareHeader(mic,h,hs)); Check(waveInAddBuffer(mic,h,hs));
    }
    Check(waveInStart(mic)); Ready=true; Events.Enqueue("READY"); string lastPartial="";
    var leadIn=new Queue<byte[]>();int leadInBytes=0;
    var utterance=new UtteranceBuffer();double noiseFloor=80;int nextHeader=0;
    while(!stopping) {
     if(activeWakeName!=WakeName){
      string changed=WakeName;IntPtr replacement=NewWakeRecognizer(model,changed);if(replacement==IntPtr.Zero)throw new Exception("Nao consegui atualizar a escuta do nome.");
      vosk_recognizer_free(wake);wake=replacement;activeWakeName=changed;wakeSent=false;
     }
     if(Paused!=previousPaused||ListeningMode!=previousMode||UseNeural!=previousNeural) {
      bool replay=!Paused&&ListeningMode&&!previousMode&&ReplayWakeAudio;
      vosk_recognizer_reset(recognizer);vosk_recognizer_reset(wake);
      utterance.Reset();
      if(replay)foreach(byte[] audio in leadIn){if(UseNeural)utterance.Seed(audio);else vosk_recognizer_accept_waveform(recognizer,audio,audio.Length);}
      leadIn.Clear();leadInBytes=0;lastPartial="";previousPaused=Paused;previousMode=ListeningMode;previousNeural=UseNeural;wakeSent=false;
     }
     // Read capture buffers in the order they were queued, including wraparound.
     for(int pending=0;pending<headers.Count;pending++) {
      IntPtr h=headers[nextHeader];
      var hd=(Header)Marshal.PtrToStructure(h,typeof(Header));
      if((hd.flags&1)==0)break;
      nextHeader=(nextHeader+1)%headers.Count;
      if(!Paused && hd.recorded>0) {
       byte[] captured=new byte[(int)hd.recorded];Marshal.Copy(hd.data,captured,0,captured.Length);
       byte[] data=converter.Convert(captured);
       if(!previousMode){leadIn.Enqueue(data);leadInBytes+=data.Length;while(leadInBytes>25600&&leadIn.Count>1)leadInBytes-=leadIn.Dequeue().Length;}
       double sum=0; for(int i=0;i+1<data.Length;i+=2){short s=(short)(data[i]|data[i+1]<<8);sum+=(double)s*s;}
       double rms=Math.Sqrt(sum/Math.Max(1,data.Length/2));Level=(float)Math.Min(1,rms/7000.0);
       if(!previousMode)noiseFloor=noiseFloor*0.98+Math.Min(rms,200)*0.02;
       if(previousMode&&previousNeural){
        byte[] audio=utterance.Push(data,rms>Math.Max(90,noiseFloor*2.5));
        if(audio!=null){Audio.Enqueue(audio);Events.Enqueue("AUDIO");}
       }else{
        IntPtr active=previousMode?recognizer:wake;
        bool final=vosk_recognizer_accept_waveform(active,data,data.Length)!=0;
        string json=Utf8(final?vosk_recognizer_result(active):vosk_recognizer_partial_result(active));
        if(previousMode){if(final){Events.Enqueue("FINAL:"+json);lastPartial="";}else if(json!=lastPartial){Events.Enqueue("PARTIAL:"+json);lastPartial=json;}}
        else {
         bool named=WakeJsonMatches(json,activeWakeName);
         if(!wakeSent&&named){Events.Enqueue("WAKE");wakeSent=true;}
         if(final&&!named)wakeSent=false;
        }
       }
      }else {Level=0;}
      if(!stopping)Check(waveInAddBuffer(mic,h,hs));
     }
     Thread.Sleep(15);
    }
   }catch(Exception ex){Events.Enqueue("ERROR:"+ex.Message);}
   finally {
    Ready=false;
    if(mic!=IntPtr.Zero) { waveInReset(mic);foreach(var h in headers)waveInUnprepareHeader(mic,h,hs);waveInClose(mic); }
    foreach(var h in headers)Marshal.FreeHGlobal(h);foreach(var b in buffers)Marshal.FreeHGlobal(b);
    if(wake!=IntPtr.Zero)vosk_recognizer_free(wake);if(recognizer!=IntPtr.Zero)vosk_recognizer_free(recognizer);if(model!=IntPtr.Zero)vosk_model_free(model);
   }
  }
  public void Dispose(){stopping=true;if(worker!=null)worker.Join(2000);}
 }
 public sealed class PcmConverter {
  readonly int rate,channels;long phase;
  public PcmConverter(int inputRate,int inputChannels){if(inputRate<16000||inputChannels<1||inputChannels>2)throw new ArgumentOutOfRangeException();rate=inputRate;channels=inputChannels;}
  public byte[] Convert(byte[] data){
   var result=new List<byte>();int frame=channels*2;
   for(int i=0;i+frame<=data.Length;i+=frame){int sum=0;for(int c=0;c<channels;c++)sum+=(short)(data[i+c*2]|data[i+c*2+1]<<8);short sample=(short)(sum/channels);phase+=16000;if(phase>=rate){phase-=rate;result.Add((byte)(sample&255));result.Add((byte)((sample>>8)&255));}}
   return result.ToArray();
  }
 }
 public static class Brain {
  public static async Task<string> Ask(string key,string body,CancellationToken token) {
   ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;
   using(var client=new HttpClient()) {
    client.Timeout=TimeSpan.FromSeconds(45);
    client.DefaultRequestHeaders.Authorization=new AuthenticationHeaderValue("Bearer",key);
    using(var content=new StringContent(body,Encoding.UTF8,"application/json"))
    using(var response=await client.PostAsync("https://api.openai.com/v1/responses",content,token).ConfigureAwait(false)) {
     string json=await response.Content.ReadAsStringAsync().ConfigureAwait(false);
     if(!response.IsSuccessStatusCode) {
      int code=(int)response.StatusCode;
      if(code==401)throw new Exception("Chave da API invalida. Abra Configurar e cadastre outra chave.");
      if(code==429)throw new Exception(LimitMessage(json));
      throw new Exception("A API retornou erro "+code+". Tente novamente mais tarde.");
     }
     return Extract(json);
    }
   }
  }
  public static string LimitMessage(string json) {
   string code="",type="";
   try {
    var root=new JavaScriptSerializer().DeserializeObject(json) as Dictionary<string,object>;
    object value;
    if(root!=null&&root.TryGetValue("error",out value)) {
     var error=value as Dictionary<string,object>;
     if(error!=null) {
      if(error.TryGetValue("code",out value)&&value is string)code=(string)value;
      if(error.TryGetValue("type",out value)&&value is string)type=(string)value;
     }
    }
   }catch{}
   if(code=="credit_balance_exhausted")return "O saldo de creditos da API acabou. Confira o faturamento na plataforma OpenAI. Criar uma chave nao adiciona creditos.";
   if(code=="insufficient_quota"||type=="insufficient_quota"||code=="organization_usage_limit_exceeded"||code.IndexOf("spend_limit",StringComparison.OrdinalIgnoreCase)>=0)
    return "A API recusou por saldo ou limite de gastos/uso. Confira o faturamento e os limites na plataforma OpenAI. Isso nao confirma que voce gastou creditos: a conta pode estar sem saldo disponivel.";
   if(code=="rate_limit_exceeded"||code=="slow_down"||type=="rate_limit_error")return "Limite temporario de velocidade da API. Aguarde um pouco antes de perguntar novamente.";
   return "A API retornou erro 429. Pode ser limite temporario, saldo ou limite de gastos. A resposta nao identificou a causa; confira sua conta na plataforma OpenAI.";
  }
  public static string Extract(string json) {
   var serializer=new JavaScriptSerializer();serializer.MaxJsonLength=4000000;
   var root=serializer.DeserializeObject(json) as Dictionary<string,object>;
   var result=new StringBuilder(); object output;
   if(root!=null&&root.TryGetValue("output",out output))foreach(object item in (object[])output) {
    var message=item as Dictionary<string,object>;object content;
    if(message!=null&&message.TryGetValue("content",out content))foreach(object c in (object[])content) {
     var part=c as Dictionary<string,object>;
     if(part!=null&&part.ContainsKey("type")&&(string)part["type"]=="output_text")result.Append((string)part["text"]);
    }
   }
   if(result.Length==0)throw new Exception("A IA nao retornou uma resposta de texto. Tente outra pergunta.");
   return result.ToString();
  }
 }
}
