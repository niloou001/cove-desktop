using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;
using System.IO;
using System.Text;
using System.Security.Cryptography;
namespace CoveApp {
 public static class Messaging {
  public static string DraftDirectory;
  static void WebProgress(string stage){
   if(String.IsNullOrWhiteSpace(DraftDirectory))return;
   try{
    var file=Path.Combine(Path.GetDirectoryName(Path.GetFullPath(DraftDirectory)),"cove-whatsapp-etapas.log");
    if(File.Exists(file)&&new FileInfo(file).Length>65536)File.WriteAllText(file,"");
    // Stage labels only; never log recipients, search values, drafts or messages.
    File.AppendAllText(file,DateTime.UtcNow.ToString("o")+" "+stage+Environment.NewLine,Encoding.UTF8);
   }catch{}
  }
  public sealed class SavedDraft {public string Id{get;set;}public string Platform{get;set;}public string Recipient{get;set;}public string Text{get;set;}public string Created{get;set;}public string Label{get{return Created+" | "+Recipient+" ("+Platform+")";}}}
  public static void BackupDraft(string platform,string recipient,string text){
   if(String.IsNullOrWhiteSpace(DraftDirectory))throw new Exception("A pasta para preservar o rascunho nao foi configurada. Mantive o texto no aplicativo.");
   byte[] raw=null;
   try{
    using(var memory=new MemoryStream()){
     using(var writer=new BinaryWriter(memory,Encoding.UTF8,true)){writer.Write("CoveDraft1");writer.Write(DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss"));writer.Write(platform);writer.Write(recipient);writer.Write(text);}
     raw=memory.ToArray();var encrypted=ProtectedData.Protect(raw,null,DataProtectionScope.CurrentUser);
     Directory.CreateDirectory(DraftDirectory);string id=Guid.NewGuid().ToString("N"),temporary=Path.Combine(DraftDirectory,id+".tmp");
     File.WriteAllBytes(temporary,encrypted);File.Move(temporary,Path.Combine(DraftDirectory,id+".dat"));
    }
   }catch{throw new Exception("Nao consegui guardar uma copia protegida do rascunho anterior. Mantive o texto no aplicativo.");}
   finally{if(raw!=null)Array.Clear(raw,0,raw.Length);}
  }
  public static SavedDraft[] ReadSavedDrafts(){
   var drafts=new List<SavedDraft>();if(String.IsNullOrWhiteSpace(DraftDirectory)||!Directory.Exists(DraftDirectory))return drafts.ToArray();
   var files=new DirectoryInfo(DraftDirectory).GetFiles("*.dat");Array.Sort(files,(a,b)=>b.CreationTimeUtc.CompareTo(a.CreationTimeUtc));
   foreach(var file in files){if(drafts.Count>=100)break;byte[] raw=null;try{
    raw=ProtectedData.Unprotect(File.ReadAllBytes(file.FullName),null,DataProtectionScope.CurrentUser);
    using(var reader=new BinaryReader(new MemoryStream(raw),Encoding.UTF8)){if(reader.ReadString()!="CoveDraft1")continue;drafts.Add(new SavedDraft{Id=file.Name,Created=reader.ReadString(),Platform=reader.ReadString(),Recipient=reader.ReadString(),Text=reader.ReadString()});}
   }finally{if(raw!=null)Array.Clear(raw,0,raw.Length);}}
   return drafts.ToArray();
  }
  public static bool IsComposer(string name,string id,string platform){
   if(platform=="Discord")return DiscordComposerName(name)||Regex.IsMatch(id??"",@"^(chat-messages-input|message-input|chat-input)(?:$|[-_])",RegexOptions.IgnoreCase);
   return Regex.IsMatch(name??"",@"^(Type a message|Digite uma mensagem|Escreva uma mensagem)(?:\.|$)",RegexOptions.IgnoreCase);
  }
  public static bool ComposerRecipientMatches(string name,string recipient){
   string target=ComposerTarget(name);return target.Length>0&&!target.StartsWith("#")&&DiscordCall.ExactName(target.TrimStart('@'),recipient);
  }
  static string ComposerTarget(string name){
   var match=Regex.Match(name??"",@"^(?:Message|Mensagem(?:\s+(?:para|a))?|Conversar\s+(?:com|em)|Enviar\s+(?:uma\s+)?mensagem\s+(?:para|a))\s+(.+?)\s*$",RegexOptions.IgnoreCase);
   return match.Success?match.Groups[1].Value:"";
  }
  public static bool DiscordComposerName(string name){return ComposerTarget(name).Length>0||Regex.IsMatch(name??"",@"^(?:Mensagem|Message|Digite uma mensagem|Escreva uma mensagem|Envie uma mensagem|Enviar uma mensagem|Enviar mensagem)[.\s]*$",RegexOptions.IgnoreCase);}
  static Condition InputTypes(){return new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Document),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Custom),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Pane));}
  static bool Contains(AutomationElement parent,AutomationElement child){
   for(int n=0;n<12&&child!=null;n++,child=TreeWalker.ControlViewWalker.GetParent(child))if(Automation.Compare(parent,child))return true;return false;
  }
  public static bool OwnsFocus(AutomationElement editor){if(editor.Current.HasKeyboardFocus)return true;var focused=AutomationElement.FocusedElement;return focused!=null&&focused.Current.ProcessId==editor.Current.ProcessId&&Contains(editor,focused);}
  public static void AcquireFocus(Func<bool> ready,Action<int> attempt,Action check,int attempts=4,int settleMilliseconds=350){
   if(attempts<1||attempts>5||settleMilliseconds<0||settleMilliseconds>1000)throw new ArgumentOutOfRangeException();
   for(int n=0;n<attempts;n++){
    try{check();if(ready())return;attempt(n);}catch(OperationCanceledException){throw;}catch(ElementNotAvailableException){}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}
    var until=DateTime.UtcNow.AddMilliseconds(settleMilliseconds);
    do{
     try{check();if(ready())return;}catch(OperationCanceledException){throw;}catch(ElementNotAvailableException){}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}
     if(DateTime.UtcNow>=until)break;Thread.Sleep(35);
    }while(true);
   }
   throw new Exception("Nao consegui focar o campo de mensagem apos "+attempts+" tentativas. Nao pressionei Enviar.");
  }
  public static AutomationElement FindDiscordComposer(AutomationElement root,string recipient,bool privateHeader){
   var matches=new List<AutomationElement>();
   foreach(AutomationElement field in root.FindAll(TreeScope.Descendants,InputTypes())){
    if(field.Current.IsOffscreen||!field.Current.IsEnabled)continue;
    string name=field.Current.Name??"",help=field.Current.HelpText??"",id=field.Current.AutomationId??"";
    if(Regex.IsMatch(name+" "+help+" "+id,@"\b(search|pesquisar|pesquisa|buscar|busca)\b|search[-_]",RegexOptions.IgnoreCase))continue;
    string target=ComposerTarget(name);if(target.Length==0)target=ComposerTarget(help);
    bool specific=ComposerRecipientMatches(name,recipient)||ComposerRecipientMatches(help,recipient);
    // The private header can use a display name while the composer uses @handle.
    // Accept that difference only with the caller's verified private header.
    if(target.Length>0&&!specific&&!(privateHeader&&target.StartsWith("@")))continue;
    if(!specific&&!(privateHeader&&(IsComposer(name,id,"Discord")||DiscordComposerName(help))))continue;
    object pattern;if(!field.TryGetCurrentPattern(ValuePattern.Pattern,out pattern)&&!field.TryGetCurrentPattern(TextPattern.Pattern,out pattern)&&!field.Current.IsKeyboardFocusable)continue;
    bool wrapper=false;
    for(int i=matches.Count-1;i>=0;i--){if(Contains(field,matches[i])){wrapper=true;break;}if(Contains(matches[i],field))matches.RemoveAt(i);}
    if(!wrapper)matches.Add(field);
   }
   return matches.Count==1?matches[0]:null;
  }
  public static string DescribeDiscordInputs(AutomationElement root){
   var log=new System.Text.StringBuilder();int count=0;
   foreach(AutomationElement field in root.FindAll(TreeScope.Descendants,InputTypes())){
    if(field.Current.IsOffscreen)continue;object value,text;bool hasValue=field.TryGetCurrentPattern(ValuePattern.Pattern,out value),hasText=field.TryGetCurrentPattern(TextPattern.Pattern,out text);
    if(!hasValue&&!hasText)continue;if(count++>=30)break;
    string name=(field.Current.Name??"").Replace("\r"," ").Replace("\n"," "),id=field.Current.AutomationId??"",help=(field.Current.HelpText??"").Replace("\r"," ").Replace("\n"," ");
    // Only editor-like labels/IDs; do not log document titles, drafts or chat text.
    if(!IsComposer(name,id,"Discord")&&!DiscordComposerName(help))continue;
    log.AppendLine("Input: "+field.Current.ControlType.ProgrammaticName+" | "+(name.Length>160?name.Substring(0,160):name)+" | "+id+" | Value="+hasValue+" Text="+hasText);
   }return log.ToString();
  }
  public static string ValidateMessage(string text){
   if(String.IsNullOrWhiteSpace(text)||text.Length>2000)throw new Exception("Diga uma mensagem de ate 2000 caracteres.");
   text=Regex.Replace(text,@"[\r\n]+"," ").Trim();if(Regex.IsMatch(text,@"[\x00-\x1F]"))throw new Exception("A mensagem contem caracteres de controle.");return text;
  }
  static string Text(AutomationElement element){
   object pattern;string value=null;
   try{if(element.TryGetCurrentPattern(ValuePattern.Pattern,out pattern)){value=((ValuePattern)pattern).Current.Value??"";if(value!=element.Current.Name||!DiscordComposerName(element.Current.Name))return NormalizeDraft(value);}}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}
   try{if(element.TryGetCurrentPattern(TextPattern.Pattern,out pattern))return NormalizeDraft(((TextPattern)pattern).DocumentRange.GetText(-1).TrimEnd('\r','\n'));}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}
   if(value!=null)return value;
   throw new InvalidOperationException("O Windows ainda nao conseguiu ler o rascunho do campo de mensagem. Nao pressionei Enviar.");
  }
  public static string NormalizeDraft(string text){return Regex.IsMatch(text??"",@"^[\s\u200B\uFEFF\u2060\uFFFC]*$")?"":text;}
  public static HashSet<string> MessageEvidence(AutomationElement root,AutomationElement editor,string text,string platform="Discord"){
   var keys=new HashSet<string>(StringComparer.Ordinal);
   foreach(AutomationElement item in root.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Group),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Document)))){
    if(item.Current.IsOffscreen)continue;
    bool content=item.Current.Name==text;object pattern;
    if(!content&&Regex.IsMatch(item.Current.AutomationId??"",@"^message-content[-_]\d",RegexOptions.IgnoreCase)&&item.TryGetCurrentPattern(TextPattern.Pattern,out pattern))content=((TextPattern)pattern).DocumentRange.GetText(text.Length+8).Trim('\r','\n')==text;
    if(!content||Contains(editor,item))continue;
    string key=null;bool messageArea=false;var current=item;
    for(int n=0;n<10&&current!=null&&!Automation.Compare(current,root);n++,current=TreeWalker.ControlViewWalker.GetParent(current)){
     string id=current.Current.AutomationId??"",name=current.Current.Name??"";
     if((platform=="WhatsApp"||platform=="WhatsApp Web")&&(current.Current.ControlType==ControlType.ListItem||current.Current.ControlType==ControlType.DataItem))messageArea=true;
     if(Regex.IsMatch(id,@"^(chat-messages|message-content)[-_]\d",RegexOptions.IgnoreCase)){key=id;messageArea=true;break;}
     if(Regex.IsMatch(name,@"^(Messages|Mensagens)(?:\s|$)",RegexOptions.IgnoreCase)&&!Regex.IsMatch(name,@"direct|diret",RegexOptions.IgnoreCase))messageArea=true;
    }
    if(messageArea){if(key==null)key="runtime:"+String.Join(".",Array.ConvertAll(item.GetRuntimeId(),id=>id.ToString()));keys.Add(key);}
   }return keys;
  }
  public static bool NewMessageAppeared(HashSet<string> before,HashSet<string> after){foreach(string key in after)if(!before.Contains(key))return true;return false;}
  public static T ReadFreshControl<T>(Func<AutomationElement> locate,Func<AutomationElement,T> read,Action check) where T:class {
   // Chromium replaces accessibility nodes after focus/layout changes. Every
   // retry must locate a new node, rather than read the invalid one again.
   return AwaitControl(()=>{var current=locate();return current==null?null:read(current);},check);
  }
  static void Check(CancellationToken token){token.ThrowIfCancellationRequested();Computer.CheckMouseCancel(token);Computer.RequireTargetForeground();}
  public static T AwaitControl<T>(Func<T> read,Action check,int timeoutMilliseconds=12000) where T:class {
   if(timeoutMilliseconds<1)throw new ArgumentOutOfRangeException();
   var clock=Stopwatch.StartNew();
   do{
    try{check();var result=read();if(result!=null)return result;}
    catch(ElementNotAvailableException){}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}
    if(clock.ElapsedMilliseconds>=timeoutMilliseconds)break;Thread.Sleep((int)Math.Max(0,Math.Min(150,timeoutMilliseconds-clock.ElapsedMilliseconds)));
   }while(true);
   throw new Exception("O campo de mensagem nao ficou acessivel apos novas tentativas. Mantive o texto; nada foi enviado.");
  }
  public static void PrepareAndSend(string text,Func<bool> recipientMatches,Func<string> readDraft,Action focus,Action<string> write,Action check,Action send){
   PrepareAndSend(text,recipientMatches,readDraft,focus,write,check,send,null);
  }
  public static void PrepareAndSend(string text,Func<bool> recipientMatches,Func<string> readDraft,Action focus,Action<string> write,Action check,Action send,Action<string> preserveDraft){
   text=ValidateMessage(text);check();
   if(!recipientMatches())throw new Exception("Nao confirmei o contato. Nada foi enviado.");
   // Chromium may expose the editable text only after the field is selected.
   focus();check();if(!recipientMatches())throw new Exception("A conversa mudou ao selecionar o campo. Nada foi enviado.");
   string previous=NormalizeDraft(readDraft());
   if(previous.Length>0&&previous!=text){if(preserveDraft==null)throw new Exception("O rascunho anterior precisa ser preservado antes de substituir o texto.");preserveDraft(previous);}
   check();
   if(NormalizeDraft(readDraft())!=previous)throw new Exception("O rascunho mudou enquanto eu preparava o envio. Preservei o texto e parei a acao.");
   if(previous!=text)write(text);check();
   var draftDeadline=DateTime.UtcNow.AddSeconds(3);
   while(readDraft()!=text){check();if(DateTime.UtcNow>=draftDeadline)throw new Exception("O campo de mensagem nao terminou de atualizar o texto esperado. Nao pressionei Enviar; confira o rascunho.");Thread.Sleep(40);}
   if(!recipientMatches())throw new Exception("A conversa mudou durante a escrita. Nao pressionei Enviar.");
   check();send();
  }
  public static string SendChecked(AutomationElement root,string recipient,string text,string platform,CancellationToken token,Func<AutomationElement,bool> verifyRecipient,Func<AutomationElement,bool> invoke){
   var recipientProbe=verifyRecipient;
   verifyRecipient=current=>AwaitControl(()=>new bool[]{recipientProbe(current)},()=>Check(token))[0];
   text=ValidateMessage(text);Check(token);if(!verifyRecipient(root))throw new Exception("Nao confirmei a conversa privada de "+recipient+". Nada foi enviado.");
   int windowHandle=root.Current.NativeWindowHandle;
   Action refresh=()=>{Check(token);if(windowHandle!=0)root=AutomationElement.FromHandle(new IntPtr(windowHandle));if(!verifyRecipient(root))throw new Exception("A conversa mudou. Nada foi enviado.");};
   var editor=AwaitControl(()=>{
   var editors=new List<AutomationElement>();
   if(platform=="Discord"){var found=FindDiscordComposer(root,recipient,true);if(found!=null)editors.Add(found);}
   else if(platform=="WhatsApp Web"){var found=WebComposer(root);if(found!=null)editors.Add(found);}
   else foreach(AutomationElement edit in root.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Document))))if(!edit.Current.IsOffscreen&&edit.Current.IsEnabled&&IsComposer(edit.Current.Name,edit.Current.AutomationId,platform))editors.Add(edit);
   return editors.Count==1?editors[0]:null;
   },refresh);
   Action focusEditor=()=>{
    AcquireFocus(()=>OwnsFocus(editor),number=>{
    if(windowHandle!=0)root=AutomationElement.FromHandle(new IntPtr(windowHandle));
    if(!verifyRecipient(root))throw new OperationCanceledException("A conversa mudou durante a tentativa de foco. Nao pressionei Enviar.");
    if(platform=="Discord"){var fresh=FindDiscordComposer(root,recipient,true);if(fresh==null)return;editor=fresh;}
    else if(platform=="WhatsApp Web"){var fresh=WebComposer(root);if(fresh==null)return;editor=fresh;}
    try{editor.SetFocus();}catch(ElementNotAvailableException){throw;}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}
    // Focusing by mouse is a click only: never use the generic Invoke path,
    // whose Enter fallback could send an existing draft.
    if(platform=="Discord"&&!OwnsFocus(editor)){if(!DiscordCall.TryFocusEditorByMouse(editor))ClickOnly(editor,token);}
    if(platform=="WhatsApp Web"&&!OwnsFocus(editor)){WebProgress("click-message-field");ClickOnly(editor,token);}
   },()=>{Check(token);if(windowHandle!=0)root=AutomationElement.FromHandle(new IntPtr(windowHandle));if(!verifyRecipient(root))throw new OperationCanceledException("A conversa mudou. Nao pressionei Enviar.");},5,800);};
   focusEditor();
   if(platform=="WhatsApp Web")WebProgress("message-field-focused");
   Func<AutomationElement> locateEditor=()=>platform=="Discord"?FindDiscordComposer(root,recipient,true):platform=="WhatsApp Web"?WebComposer(root):editor;
   if(platform=="WhatsApp Web")WebProgress("read-message-baseline");
   var before=ReadFreshControl(locateEditor,fresh=>{
    editor=fresh;var scope=platform=="WhatsApp Web"?WebDocument(root):root;
    return scope==null?null:MessageEvidence(scope,fresh,text,platform);
   },refresh);
   if(platform=="WhatsApp Web")WebProgress("message-baseline-ready");
   Func<string> readEditor=()=>AwaitControl(()=>{
    var fresh=platform=="Discord"?FindDiscordComposer(root,recipient,true):platform=="WhatsApp Web"?WebComposer(root):editor;
    if(fresh==null)return null;editor=fresh;return Text(editor);
   },refresh);
   PrepareAndSend(text,()=>verifyRecipient(root),readEditor,focusEditor,body=>{object value;if(platform=="WhatsApp"&&editor.TryGetCurrentPattern(ValuePattern.Pattern,out value)&&!((ValuePattern)value).Current.IsReadOnly)((ValuePattern)value).SetValue(body);else {
    if(platform=="WhatsApp Web")WebProgress("type-message");
    if(!OwnsFocus(editor))throw new Exception("O foco saiu do campo de mensagem. Nada foi enviado.");
    Computer.Press(65,true,false,false);if(!OwnsFocus(editor))throw new Exception("O foco mudou. Mantive o rascunho salvo.");Computer.Press(8,false,false,false);
    if(!OwnsFocus(editor))throw new Exception("O foco mudou antes de escrever. Mantive o rascunho salvo.");Computer.Type(body);
   }},()=>Check(token),()=>{
   var sends=new List<AutomationElement>();
   var sendScope=platform=="WhatsApp Web"?WebDocument(root):root;
   if(sendScope==null)throw new Exception("O WhatsApp Web saiu da tela esperada. Nao pressionei Enviar.");
   foreach(AutomationElement button in sendScope.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)))if(!button.Current.IsOffscreen&&button.Current.IsEnabled&&Regex.IsMatch(button.Current.Name??"",@"^(Send|Send message|Enviar|Enviar mensagem)$",RegexOptions.IgnoreCase))sends.Add(button);
   Check(token);
   // Discord often hides Send. Enter is used only after recipient, draft and focus checks.
   if(sends.Count==1){if(!invoke(sends[0]))throw new Exception("Nao consegui acionar Enviar. Confira o rascunho.");}
   else if(sends.Count==0&&platform=="Discord"){
    if(!OwnsFocus(editor))focusEditor();
    if(Text(editor)!=text)throw new Exception("O rascunho mudou ao recuperar o foco. Nao pressionei Enviar.");Computer.Press(13,false,false,false);
   }else throw new Exception("Nao identifiquei um unico botao Enviar. Confira o rascunho.");
   },draft=>BackupDraft(platform,recipient,draft));
   if(platform=="WhatsApp Web")WebProgress("send-clicked");
   // Never retry a send: a delayed UI update must not duplicate a message.
   var until=DateTime.UtcNow.AddSeconds(6);
   while(DateTime.UtcNow<until){
    if(token.IsCancellationRequested)break;Thread.Sleep(150);
    try{
     if(windowHandle!=0)root=AutomationElement.FromHandle(new IntPtr(windowHandle));
     if(!verifyRecipient(root))continue;
     var fresh=platform=="Discord"?FindDiscordComposer(root,recipient,true):platform=="WhatsApp Web"?WebComposer(root):editor;
     if(fresh!=null&&String.IsNullOrWhiteSpace(Text(fresh))){
      var scope=platform=="WhatsApp Web"?WebDocument(root):root;
      if(scope!=null&&NewMessageAppeared(before,MessageEvidence(scope,fresh,text,platform))){if(platform=="WhatsApp Web")WebProgress("send-verified");return "Mensagem enviada para "+recipient+" no "+platform+".";}
     }
    }catch(ElementNotAvailableException){}catch(System.Runtime.InteropServices.COMException){}
   }
   try{if(verifyRecipient(root)&&Text(editor)==text)return "O texto continua no rascunho de "+recipient+" no "+platform+". O envio nao foi concluido.";}catch(ElementNotAvailableException){}
   return "Cliquei em Enviar para "+recipient+" no "+platform+". Confira a conversa antes de repetir o pedido.";
  }
  static AutomationElement WhatsAppRoot(){foreach(var process in Process.GetProcessesByName("WhatsApp")){using(process){try{if(process.MainWindowHandle!=IntPtr.Zero)return AutomationElement.FromHandle(process.MainWindowHandle);}catch{}}}return null;}
  static string[] Details(AutomationElement item){var values=new List<string>{item.Current.Name??""};foreach(AutomationElement text in item.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text)))if(!text.Current.IsOffscreen)values.Add(text.Current.Name??"");return values.ToArray();}
  public static bool IsWhatsAppWebAddress(string value){
   Uri uri;value=(value??"").Trim();if(!value.Contains("://"))value="https://"+value;
   return Uri.TryCreate(value,UriKind.Absolute,out uri)&&uri.Scheme=="https"&&uri.Host.Equals("web.whatsapp.com",StringComparison.OrdinalIgnoreCase)&&uri.IsDefaultPort&&uri.UserInfo.Length==0;
  }
  static bool BrowserIsWhatsApp(AutomationElement root){
   foreach(AutomationElement field in root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit))){
    if(field.Current.IsOffscreen||!Regex.IsMatch((field.Current.Name??"")+" "+field.Current.AutomationId,@"address and search|endere[cç]o.*pesquisa|pesquisa.*endere[cç]o|omnibox",RegexOptions.IgnoreCase))continue;
    bool pageField=false;var ancestor=TreeWalker.ControlViewWalker.GetParent(field);
    for(int n=0;n<20&&ancestor!=null&&!Automation.Compare(ancestor,root);n++,ancestor=TreeWalker.ControlViewWalker.GetParent(ancestor))if(ancestor.Current.ControlType==ControlType.Document){pageField=true;break;}
    object value;if(!pageField&&field.TryGetCurrentPattern(ValuePattern.Pattern,out value)&&IsWhatsAppWebAddress(((ValuePattern)value).Current.Value))return true;
   }return false;
  }
  static AutomationElement WebRoot(){
   var candidates=new List<AutomationElement>();
   foreach(AutomationElement root in AutomationElement.RootElement.FindAll(TreeScope.Children,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Window))){
    try{
     if(root.Current.IsOffscreen||(root.Current.Name??"").IndexOf("WhatsApp",StringComparison.OrdinalIgnoreCase)<0)continue;
     using(var process=Process.GetProcessById(root.Current.ProcessId))if(!process.ProcessName.Equals("chrome",StringComparison.OrdinalIgnoreCase))continue;
     if(BrowserIsWhatsApp(root))candidates.Add(root);
    }catch(ElementNotAvailableException){}catch(System.Runtime.InteropServices.COMException){}
   }
   foreach(var candidate in candidates)if(candidate.Current.NativeWindowHandle==Computer.ForegroundHandle())return candidate;
   if(candidates.Count>1)throw new Exception("Ha mais de uma janela do WhatsApp Web. Deixe ativa a conta que voce quer usar e tente novamente.");
   return candidates.Count==1?candidates[0]:null;
  }
  static AutomationElement WebDocument(AutomationElement root){
   if(root==null||!BrowserIsWhatsApp(root))return null;
   foreach(AutomationElement document in root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Document)))if(!document.Current.IsOffscreen&&(document.Current.Name??"").IndexOf("WhatsApp",StringComparison.OrdinalIgnoreCase)>=0)return document;
   return null;
  }
  static AutomationElement WebComposer(AutomationElement root){
   var doc=WebDocument(root);if(doc==null)return null;var matches=new List<AutomationElement>();
   foreach(AutomationElement field in doc.FindAll(TreeScope.Descendants,InputTypes())){
    if(field.Current.IsOffscreen||!field.Current.IsEnabled||!(IsComposer(field.Current.Name,field.Current.AutomationId,"WhatsApp")||IsComposer(field.Current.HelpText,field.Current.AutomationId,"WhatsApp")))continue;
    object pattern;if(!field.TryGetCurrentPattern(ValuePattern.Pattern,out pattern)&&!field.TryGetCurrentPattern(TextPattern.Pattern,out pattern)&&!field.Current.IsKeyboardFocusable)continue;
    bool wrapper=false;for(int i=matches.Count-1;i>=0;i--){if(Contains(field,matches[i])){wrapper=true;break;}if(Contains(matches[i],field))matches.RemoveAt(i);}
    if(!wrapper)matches.Add(field);
   }return matches.Count==1?matches[0]:null;
  }
  static AutomationElement WebContactPanel(AutomationElement root){
   var doc=WebDocument(root);if(doc==null)return null;
   foreach(AutomationElement area in doc.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Group),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Pane),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Window),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Custom))))if(!area.Current.IsOffscreen&&Regex.IsMatch(area.Current.Name??"",@"^(Nova conversa|New chat|Contatos no WhatsApp|Contacts on WhatsApp)$",RegexOptions.IgnoreCase))return area;
   // Some Chromium versions expose "Nova conversa" only as a heading Text;
   // its container has no name. Find the closest container with a search field,
   // without ever expanding to the document or a background message composer.
   foreach(AutomationElement title in doc.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text))){
    if(title.Current.IsOffscreen||!Regex.IsMatch(title.Current.Name??"",@"^(Nova conversa|New chat|Contatos no WhatsApp|Contacts on WhatsApp)$",RegexOptions.IgnoreCase))continue;
    var area=TreeWalker.ControlViewWalker.GetParent(title);
    for(int n=0;n<5&&area!=null&&!Automation.Compare(area,doc);n++,area=TreeWalker.ControlViewWalker.GetParent(area)){
     bool hasComposer=false;foreach(AutomationElement input in area.FindAll(TreeScope.Descendants,InputTypes()))if(IsComposer(input.Current.Name,input.Current.AutomationId,"WhatsApp")){hasComposer=true;break;}
     if(!hasComposer&&WebContactSearch(area)!=null)return area;
    }
   }
   return null;
  }
  static AutomationElement WebContactSearch(AutomationElement panel){
   var fields=new List<AutomationElement>();var unnamed=new List<AutomationElement>();
   foreach(AutomationElement field in panel.FindAll(TreeScope.Descendants,InputTypes())){
    if(field.Current.IsOffscreen||!field.Current.IsEnabled||!field.Current.IsKeyboardFocusable)continue;
    object value,text;bool hasValue=field.TryGetCurrentPattern(ValuePattern.Pattern,out value),hasText=field.TryGetCurrentPattern(TextPattern.Pattern,out text);
    if(!hasValue&&!hasText)continue;if(hasValue&&((ValuePattern)value).Current.IsReadOnly)continue;
    string label=(field.Current.Name??"")+" "+field.Current.HelpText+" "+field.Current.AutomationId;
    if(IsComposer(field.Current.Name,field.Current.AutomationId,"WhatsApp"))continue;
    bool named=Regex.IsMatch(label,@"search|pesquis|buscar|nome|name|n[uú]mero|number",RegexOptions.IgnoreCase);
    // Chromium sometimes exposes only the placeholder/help text, or one unnamed
    // editable textbox. A unique input inside the verified picker is sufficient.
    if(!named&&field.Current.ControlType!=ControlType.Edit&&field.Current.ControlType!=ControlType.Document)continue;
    var candidates=named?fields:unnamed;
    bool wrapper=false;for(int i=candidates.Count-1;i>=0;i--){if(Contains(field,candidates[i])){wrapper=true;break;}if(Contains(candidates[i],field))candidates.RemoveAt(i);}if(!wrapper)candidates.Add(field);
   }return fields.Count==1?fields[0]:fields.Count==0&&unnamed.Count==1?unnamed[0]:null;
  }
  public static void EnterContactSearch(string recipient,Func<bool> focused,Action<int> focus,Action<string> replace,Func<string> read,Action check,int settleMilliseconds=1200){
   if(String.IsNullOrWhiteSpace(recipient)||recipient.Length>100||settleMilliseconds<1)throw new ArgumentException("Busca de contato invalida.");
   for(int attempt=0;attempt<3;attempt++){
    try{
     check();focus(attempt);
     AcquireFocus(focused,number=>focus(attempt+number),check,3,350);
     check();if(!focused())throw new OperationCanceledException("O foco saiu da busca. Nada foi enviado.");
     replace(recipient);
     var clock=Stopwatch.StartNew();
     do{check();if(DiscordCall.ExactName(read(),recipient))return;if(clock.ElapsedMilliseconds>=settleMilliseconds)break;Thread.Sleep(60);}while(true);
    }catch(ElementNotAvailableException){}catch(System.Runtime.InteropServices.COMException){}
   }
   throw new Exception("Nao consegui preencher a busca com o nome do contato apos 3 tentativas. Nada foi enviado.");
  }
  static List<AutomationElement> WebContacts(AutomationElement panel,string recipient){
   var matches=new List<AutomationElement>();
   // Click the matching name itself, never the centre of a wrapper that may
   // include an avatar, a second result, or the previous chat's preview.
   foreach(AutomationElement item in panel.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Hyperlink),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.ListItem),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.DataItem),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Custom),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Group)))){
    if(item.Current.IsOffscreen||!DiscordCall.ExactName(item.Current.Name,recipient))continue;
    var bounds=item.Current.BoundingRectangle;if(bounds.IsEmpty||bounds.Height>90)continue;
    var row=TreeWalker.ControlViewWalker.GetParent(item);bool valid=true;
    for(int depth=0;depth<5&&row!=null&&!Automation.Compare(row,panel);depth++,row=TreeWalker.ControlViewWalker.GetParent(row)){
     var rect=row.Current.BoundingRectangle;if(rect.Height>180)break;
     bool input=false;foreach(AutomationElement field in row.FindAll(TreeScope.Descendants,InputTypes()))if(field.Current.IsKeyboardFocusable){input=true;break;}
     if(input)break;
     var kind=row.Current.ControlType;
     // Only a semantic result row can reject a status match. Anonymous layout
     // wrappers can contain several results and are not contact identities.
     if(kind!=ControlType.ListItem&&kind!=ControlType.DataItem&&kind!=ControlType.Button&&kind!=ControlType.Group)continue;
     var texts=row.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text));
     string first="";foreach(AutomationElement label in texts)if(!label.Current.IsOffscreen&&!String.IsNullOrWhiteSpace(label.Current.Name)&&!Regex.IsMatch(label.Current.Name,@"^(?:foto de perfil|profile photo|outra foto|avatar)$",RegexOptions.IgnoreCase)){first=label.Current.Name;break;}
     // A match in the status/preview of somebody else's row is not identity.
     if(first.Length>0&&!DiscordCall.ExactName(first,recipient)){valid=false;break;}
     if(!ContactResult(recipient,Details(row),recipient)){valid=false;break;}
     break;
    }
    if(valid){bool wrapper=false;for(int i=matches.Count-1;i>=0;i--){if(Contains(item,matches[i])){wrapper=true;break;}if(Contains(matches[i],item))matches.RemoveAt(i);}if(!wrapper)matches.Add(item);}
   }return matches;
  }
  static bool RawContains(AutomationElement parent,AutomationElement child){
   for(int n=0;n<128&&child!=null;n++,child=TreeWalker.RawViewWalker.GetParent(child))if(Automation.Compare(parent,child))return true;return false;
  }
  public static bool CanClickElementAt(AutomationElement target,AutomationElement hit,long hitWindow,long expectedWindow){
   if(target==null||hit==null||expectedWindow==0||hitWindow!=expectedWindow)return false;
   if(RawContains(target,hit))return true;
   // Chromium's point provider may return the enclosing input/document rather
   // than its accessible child. A real native-window hit check is still required.
   var type=hit.Current.ControlType;
   bool enclosing=type==ControlType.Document||type==ControlType.Pane||type==ControlType.Custom||type==ControlType.Group||type==ControlType.Edit||type==ControlType.Button;
   return enclosing&&RawContains(hit,target);
  }
  static bool FindClickPoint(AutomationElement element,System.Windows.Rect bounds,out System.Windows.Point point,out bool covered){
   var points=new List<System.Windows.Point>();System.Windows.Point preferred;
   points.Add(new System.Windows.Point(bounds.Left+bounds.Width/2,bounds.Top+bounds.Height/2));
   try{if(element.TryGetClickablePoint(out preferred))points.Add(preferred);}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}
   points.Add(new System.Windows.Point(bounds.Left+Math.Min(12,bounds.Width/3),bounds.Top+bounds.Height/2));
   points.Add(new System.Windows.Point(bounds.Right-Math.Min(12,bounds.Width/3),bounds.Top+bounds.Height/2));
   bool sawTarget=false,sawOther=false;
   foreach(var candidate in points){
    var exact=new System.Windows.Point(Math.Round(candidate.X),Math.Round(candidate.Y));if(!bounds.Contains(exact))continue;
    long window=Computer.WindowAtPoint((int)exact.X,(int)exact.Y);
    if(window==Computer.Target)sawTarget=true;else if(window!=0)sawOther=true;
    if(window!=Computer.Target)continue;
    var hit=AutomationElement.FromPoint(exact);
    if(CanClickElementAt(element,hit,window,Computer.Target)){point=exact;covered=false;return true;}
   }
   point=new System.Windows.Point();covered=sawOther&&!sawTarget;return false;
  }
  static bool ClickOnly(AutomationElement element,CancellationToken token){
   using(new Computer.PhysicalCoordinates()){
    Check(token);var bounds=element.Current.BoundingRectangle;if(element.Current.IsOffscreen||!element.Current.IsEnabled||bounds.IsEmpty||bounds.Width<3||bounds.Height<3)return false;
    System.Windows.Point point;bool covered;
    bool found=false;point=new System.Windows.Point();covered=false;
    for(int attempt=0;attempt<3;attempt++){
     Check(token);bounds=element.Current.BoundingRectangle;
     if(element.Current.IsOffscreen||!element.Current.IsEnabled||bounds.IsEmpty)return false;
     if(FindClickPoint(element,bounds,out point,out covered)){found=true;break;}
     if(attempt<2)Thread.Sleep(120);
    }
    if(!found){
     WebProgress(covered?"click-blocked-other-window":"click-point-not-ready");
     throw new OperationCanceledException(covered?"Outra janela esta sobre o campo. Parei antes de clicar.":"O Chrome nao informou um ponto seguro para clicar no campo. Nada foi enviado.");
    }
    Computer.MoveSmooth((int)Math.Round(point.X),(int)Math.Round(point.Y),token);
    var after=element.Current.BoundingRectangle;if(Math.Abs(after.Left-bounds.Left)>2||Math.Abs(after.Top-bounds.Top)>2||Math.Abs(after.Width-bounds.Width)>2||Math.Abs(after.Height-bounds.Height)>2)throw new OperationCanceledException("O campo mudou de posicao. Nao cliquei.");
    var hit=AutomationElement.FromPoint(point);
    if(!CanClickElementAt(element,hit,Computer.WindowAtPoint((int)point.X,(int)point.Y),Computer.Target))throw new OperationCanceledException("O alvo do clique mudou. Nao cliquei.");
    Computer.ClickFocusedTarget((int)Math.Round(point.X),(int)Math.Round(point.Y),token);return true;
   }
  }
  static bool WebInvoke(AutomationElement element,CancellationToken token){object pattern;Check(token);if(element.TryGetCurrentPattern(InvokePattern.Pattern,out pattern)){((InvokePattern)pattern).Invoke();return true;}return ClickOnly(element,token);}
  static bool OpenWebContact(AutomationElement name,AutomationElement panel,string recipient,CancellationToken token){
   Check(token);if(!DiscordCall.ExactName(name.Current.Name,recipient)||!Contains(panel,name))throw new OperationCanceledException("O resultado da busca mudou. Nao abri outro contato.");
   var current=name;
   for(int depth=0;depth<5&&current!=null&&!Automation.Compare(current,panel);depth++,current=TreeWalker.ControlViewWalker.GetParent(current)){
    var rect=current.Current.BoundingRectangle;if(rect.IsEmpty||rect.Height>90)break;
    if(!Automation.Compare(current,name)&&!DiscordCall.ExactName(current.Current.Name,recipient))continue;
    object pattern;
    if(current.TryGetCurrentPattern(InvokePattern.Pattern,out pattern)){WebProgress("invoke-contact");((InvokePattern)pattern).Invoke();return true;}
    if(current.TryGetCurrentPattern(SelectionItemPattern.Pattern,out pattern)){WebProgress("select-contact");((SelectionItemPattern)pattern).Select();return true;}
   }
   WebProgress("click-exact-contact-name");return ClickOnly(name,token);
  }
  public static AutomationElement WaitForWebContacts(Func<AutomationElement> ready,Func<bool> opening,Func<int,bool> requestOpen,Action check,int timeoutMilliseconds=45000,int retryMilliseconds=15000){
   if(timeoutMilliseconds<1||retryMilliseconds<1)throw new ArgumentOutOfRangeException();
   var clock=Stopwatch.StartNew();long nextAttempt=0;int attempts=0;
   while(clock.ElapsedMilliseconds<timeoutMilliseconds){
    check();
    try{
     var panel=ready();if(panel!=null)return panel;
     if(attempts<3&&clock.ElapsedMilliseconds>=nextAttempt&&!opening()){
      // Recheck immediately before clicking: a delayed picker may have appeared
      // since the previous poll. Never toggle a picker that is already opening.
      check();panel=ready();if(panel!=null)return panel;
      if(!opening()){
       bool requested=requestOpen(attempts);
       if(requested)attempts++;
       nextAttempt=clock.ElapsedMilliseconds+(requested?retryMilliseconds:500);
      }
     }
    }catch(ElementNotAvailableException){nextAttempt=Math.Max(nextAttempt,clock.ElapsedMilliseconds+300);}
     catch(System.Runtime.InteropServices.COMException){nextAttempt=Math.Max(nextAttempt,clock.ElapsedMilliseconds+300);}
    Thread.Sleep((int)Math.Min(150,Math.Max(1,timeoutMilliseconds-clock.ElapsedMilliseconds)));
   }
   check();return ready();
  }
  static bool WebHeader(AutomationElement root,string recipient){
   var doc=WebDocument(root);var composer=WebComposer(root);if(doc==null||composer==null||WebContactPanel(root)!=null)return false;
   var page=doc.Current.BoundingRectangle;var input=composer.Current.BoundingRectangle;bool found=false;
   foreach(AutomationElement item in doc.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Group),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Custom)))){
    if(item.Current.IsOffscreen)continue;var rect=item.Current.BoundingRectangle;if(rect.IsEmpty||rect.Top>page.Top+160||rect.Left<input.Left-120)continue;
    string label=item.Current.Name??"";if(Regex.IsMatch(label,@"group info|dados do grupo|informa[cç][oõ]es do grupo",RegexOptions.IgnoreCase))return false;
    if(rect.Height<=100&&DiscordCall.ExactName(label,recipient))found=true;
   }return found;
  }
  public static bool WaitForWebConversation(Func<bool> ready,Action check,Action retrySelection,int timeoutMilliseconds=45000,int stableMilliseconds=800){
   if(timeoutMilliseconds<1||stableMilliseconds<0)throw new ArgumentOutOfRangeException();
   var clock=Stopwatch.StartNew();long readySince=-1;
   while(clock.ElapsedMilliseconds<timeoutMilliseconds){
    check();
    try{
     if(ready()){
      if(readySince<0)readySince=clock.ElapsedMilliseconds;
      if(clock.ElapsedMilliseconds-readySince>=stableMilliseconds)return true;
     }else{readySince=-1;if(retrySelection!=null)retrySelection();}
    }catch(ElementNotAvailableException){readySince=-1;}
     catch(System.Runtime.InteropServices.COMException){readySince=-1;}
    Thread.Sleep((int)Math.Min(150,Math.Max(1,timeoutMilliseconds-clock.ElapsedMilliseconds)));
   }
   check();return false;
  }
  public static Task<string> SendWhatsAppWeb(string recipient,string message,string chrome,CancellationToken token){return Task.Run(()=>{
   using(new Computer.PhysicalCoordinates()){
    string stage="abrir WhatsApp Web";
    WebProgress("open-web");
    try{
     message=ValidateMessage(message);if(String.IsNullOrWhiteSpace(recipient)||recipient.Length>100||Regex.IsMatch(recipient,@"[\x00-\x1F]"))throw new Exception("Informe o nome do contato salvo no WhatsApp.");
     var root=WebRoot();if(root==null)Process.Start(new ProcessStartInfo(chrome,"--new-window https://web.whatsapp.com/"){UseShellExecute=true});
     var until=DateTime.UtcNow.AddSeconds(20);while(root==null&&DateTime.UtcNow<until){token.ThrowIfCancellationRequested();Thread.Sleep(200);root=WebRoot();}
     if(root==null)throw new Exception("Nao consegui acessar web.whatsapp.com no Chrome. Abra o site e entre na sua conta.");
     // Scope recovery to this worker and this exact window. Global mouse commands
     // retain their existing cancellation behavior when the foreground changes.
     long webHandle=root.Current.NativeWindowHandle;
     using(new Computer.RecoverWindowFocus(webHandle)){
     Computer.Target=webHandle;Check(token);stage="abrir contatos";WebProgress("open-contact-picker");AutomationElement observedPanel=null;
     var panel=WaitForWebContacts(()=>{
      observedPanel=WebContactPanel(root);
      if(observedPanel==null)return null;
      var field=WebContactSearch(observedPanel);
      return field!=null&&field.Current.IsEnabled?observedPanel:null;
     },()=>observedPanel!=null,attempt=>{
      var doc=WebDocument(root);if(doc==null)return false;
      // A visible title also means the picker is opening, even if Chromium has
      // not exposed its container/search field yet.
      foreach(AutomationElement label in doc.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text)))if(!label.Current.IsOffscreen&&Regex.IsMatch(label.Current.Name??"",@"^(Nova conversa|New chat|Contatos no WhatsApp|Contacts on WhatsApp)$",RegexOptions.IgnoreCase))return false;
      foreach(AutomationElement button in doc.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)))if(!button.Current.IsOffscreen&&button.Current.IsEnabled&&Regex.IsMatch(button.Current.Name??"",@"^(Nova conversa|New chat)(?:\s*\(|\s+Ctrl|$)",RegexOptions.IgnoreCase))return attempt==0?WebInvoke(button,token):ClickOnly(button,token);
      return false;
     },()=>{Check(token);if(!BrowserIsWhatsApp(root))throw new OperationCanceledException("A aba saiu do WhatsApp Web. Nada foi enviado.");});
     if(panel==null)throw new Exception("Aguardei ate 45 segundos e tentei abrir os contatos ate 3 vezes, mas a lista ou a busca ainda nao ficou pronta. Nada foi enviado.");
     stage="buscar contato";WebProgress("find-search-field");var search=WebContactSearch(panel);
     if(search==null)throw new Exception("Nao identifiquei uma busca unica de contatos no WhatsApp Web.");
     Action checkSearch=()=>{
      Check(token);if(!BrowserIsWhatsApp(root))throw new OperationCanceledException("A aba saiu do WhatsApp Web. Nada foi enviado.");
      var currentPanel=WebContactPanel(root);if(currentPanel==null)throw new OperationCanceledException("A lista de contatos foi fechada. Nada foi enviado.");
      var fresh=WebContactSearch(currentPanel);if(fresh==null)throw new ElementNotAvailableException();search=fresh;
     };
     EnterContactSearch(recipient,()=>OwnsFocus(search),attempt=>{
      WebProgress("click-search-field");
      ClickOnly(search,token);
      if(attempt>0&&!OwnsFocus(search)){try{search.SetFocus();}catch(InvalidOperationException){}}
     },name=>{
      WebProgress("type-contact-name");
      if(!OwnsFocus(search))throw new OperationCanceledException("O foco saiu da busca. Nada foi enviado.");
      Computer.Press(65,true,false,false);
      if(!OwnsFocus(search))throw new OperationCanceledException("O foco mudou antes de pesquisar. Nada foi enviado.");
      Computer.Type(name);
     },()=>Text(search),checkSearch);
     WebProgress("search-text-verified");
     bool selected=false;int selectionAttempts=0;long nextSelection=0,nextDiagnostic=0;var selectionClock=Stopwatch.StartNew();
     WebProgress("wait-conversation-ready");stage="aguardar conversa";
     bool conversationReady=WaitForWebConversation(()=>selected&&WebHeader(root,recipient),()=>{
      Check(token);if(!BrowserIsWhatsApp(root))throw new OperationCanceledException("A aba saiu do WhatsApp Web. Nada foi enviado.");
     },()=>{
      // Once the picker disappears, only wait. Never click coordinates from
      // the former contact list while the conversation is loading.
      panel=WebContactPanel(root);if(panel==null)return;
      var matches=WebContacts(panel,recipient);
      if(selectionClock.ElapsedMilliseconds>=nextDiagnostic){WebProgress("exact-contact-results: "+matches.Count);nextDiagnostic=selectionClock.ElapsedMilliseconds+5000;}
      if(matches.Count>1)throw new Exception("Ha mais de um contato chamado "+recipient+". Use o nome completo salvo na agenda.");
      if(matches.Count==1&&selectionAttempts<3&&selectionClock.ElapsedMilliseconds>=nextSelection){
       search=WebContactSearch(panel);if(search==null||!DiscordCall.ExactName(Text(search),recipient))throw new OperationCanceledException("A busca de contatos mudou. Nada foi enviado.");
       stage="abrir conversa";
       WebProgress("click-contact-row");
       bool clicked=OpenWebContact(matches[0],panel,recipient,token);
       selected=selected||clicked;selectionAttempts++;nextSelection=selectionClock.ElapsedMilliseconds+15000;
       stage="aguardar conversa";WebProgress("wait-conversation-ready");
      }
     });
     if(conversationReady){WebProgress("conversation-ready-stable");stage="enviar mensagem";return SendChecked(root,recipient,message,"WhatsApp Web",token,current=>WebHeader(current,recipient),button=>ClickOnly(button,token));}
     if(!selected)throw new Exception("Nao encontrei um contato unico chamado "+recipient+" no WhatsApp Web.");
     throw new Exception("Aguardei ate 45 segundos, mas a conversa e o campo de mensagem nao ficaram prontos. Nada foi enviado.");
     }
    }catch(OperationCanceledException){WebProgress("cancelled: "+stage);throw;}catch(Exception error){WebProgress("failed: "+stage+" ["+error.GetBaseException().GetType().Name+"]");if(String.IsNullOrWhiteSpace(error.GetBaseException().Message))throw new Exception("Nao consegui concluir a etapa "+stage+" apos tentar recuperar os controles. Nada sera reenviado automaticamente; o texto permanece no Cove.");throw;}
   }
  },token);}
  public static bool ContactResult(string label,string[] details,string recipient){
   if(Regex.IsMatch(String.Join(" ",details),@"\b(group|grupo|community|comunidade)\b",RegexOptions.IgnoreCase))return false;
   if(DiscordCall.ExactName(label,recipient))return true;
   foreach(string detail in details)if(DiscordCall.ExactName(detail,recipient))return true;
   return false;
  }
  static bool WhatsAppHeader(AutomationElement root,string recipient){
   foreach(AutomationElement bar in root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.ToolBar))){
    if(bar.Current.IsOffscreen)continue;var details=Details(bar);bool found=false,group=false,contact=false;
    foreach(string name in details){if(DiscordCall.ExactName(name,recipient))found=true;if(Regex.IsMatch(name,@"\b(group info|dados do grupo|info do grupo|participantes|members)\b",RegexOptions.IgnoreCase))group=true;}
    foreach(AutomationElement button in bar.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)))if(Regex.IsMatch(button.Current.Name+" "+button.Current.HelpText,@"contact info|dados do contato|info(?:rma[cç][oõ]es)? do contato",RegexOptions.IgnoreCase))contact=true;
    if(found&&!group&&contact)return true;
   }return false;
  }
  public static Task<string> SendWhatsApp(string recipient,string message,CancellationToken token){return Task.Run(()=>{
   message=ValidateMessage(message);AutomationElement root=WhatsAppRoot();if(root==null)Process.Start(new ProcessStartInfo("whatsapp://"){UseShellExecute=true});
   var until=DateTime.UtcNow.AddSeconds(12);while(root==null&&DateTime.UtcNow<until){token.ThrowIfCancellationRequested();Thread.Sleep(200);root=WhatsAppRoot();}
   if(root==null)throw new Exception("Abra o WhatsApp Desktop e entre na sua conta para enviar mensagens.");
   Computer.FocusHandle(root.Current.NativeWindowHandle);Check(token);Computer.Press(78,true,false,false);Thread.Sleep(350);
   var search=AutomationElement.FocusedElement;object value;
   if(search==null||search.Current.ProcessId!=root.Current.ProcessId||search.Current.ControlType!=ControlType.Edit||!Regex.IsMatch(search.Current.Name??"",@"search|pesquis|buscar|nome|name|numero|n[uú]mero|number",RegexOptions.IgnoreCase)||!search.TryGetCurrentPattern(ValuePattern.Pattern,out value))throw new Exception("Nao confirmei a busca de contatos do WhatsApp. Nada foi enviado.");
   ((ValuePattern)value).SetValue(recipient);Thread.Sleep(400);bool selected=false;until=DateTime.UtcNow.AddSeconds(5);
   while(DateTime.UtcNow<until&&!selected){
    Check(token);root=WhatsAppRoot();var matches=new List<AutomationElement>();
    foreach(AutomationElement item in root.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.ListItem),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.DataItem))))if(!item.Current.IsOffscreen&&ContactResult(item.Current.Name,Details(item),recipient))matches.Add(item);
    if(matches.Count>1)throw new Exception("Encontrei mais de um contato com esse nome no WhatsApp. Diga o nome completo salvo na agenda.");
    if(matches.Count==1){object pattern;var item=matches[0];if(item.TryGetCurrentPattern(InvokePattern.Pattern,out pattern)){((InvokePattern)pattern).Invoke();selected=true;}else if(item.TryGetCurrentPattern(SelectionItemPattern.Pattern,out pattern)){((SelectionItemPattern)pattern).Select();item.SetFocus();Computer.Press(13,false,false,false);selected=true;}}
    if(!selected)Thread.Sleep(150);
   }
   if(!selected)throw new Exception("Nao encontrei um contato unico chamado "+recipient+" no WhatsApp. Nada foi enviado.");
   until=DateTime.UtcNow.AddSeconds(4);while(DateTime.UtcNow<until){Check(token);Thread.Sleep(150);root=WhatsAppRoot();if(WhatsAppHeader(root,recipient))return SendChecked(root,recipient,message,"WhatsApp",token,fresh=>WhatsAppHeader(fresh,recipient),button=>{object pattern;if(!button.TryGetCurrentPattern(InvokePattern.Pattern,out pattern))return false;((InvokePattern)pattern).Invoke();return true;});}
   throw new Exception("Nao confirmei o contato no cabecalho da conversa do WhatsApp. Nada foi enviado.");
  },token);}
 }
}
