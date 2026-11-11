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
    if(target.Length>0&&!specific)continue;
    if(!specific&&!(privateHeader&&(IsComposer(name,id,"Discord")||DiscordComposerName(help))))continue;
    object pattern;if(!field.TryGetCurrentPattern(ValuePattern.Pattern,out pattern)&&!field.TryGetCurrentPattern(TextPattern.Pattern,out pattern))continue;
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
   throw new Exception("O Windows nao conseguiu ler o rascunho do campo de mensagem. Nao pressionei Enviar.");
  }
  public static string NormalizeDraft(string text){return Regex.IsMatch(text??"",@"^[\s\u200B\uFEFF\u2060\uFFFC]*$")?"":text;}
  public static HashSet<string> MessageEvidence(AutomationElement root,AutomationElement editor,string text,string platform="Discord"){
   var keys=new HashSet<string>(StringComparer.Ordinal);
   foreach(AutomationElement item in root.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Group),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Document)))){
    if(item.Current.IsOffscreen||Contains(editor,item))continue;
    bool content=item.Current.Name==text;object pattern;
    if(!content&&Regex.IsMatch(item.Current.AutomationId??"",@"^message-content[-_]\d",RegexOptions.IgnoreCase)&&item.TryGetCurrentPattern(TextPattern.Pattern,out pattern))content=((TextPattern)pattern).DocumentRange.GetText(text.Length+8).Trim('\r','\n')==text;
    if(!content)continue;
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
  static void Check(CancellationToken token){token.ThrowIfCancellationRequested();Computer.CheckMouseCancel(token);Computer.RequireTargetForeground();}
  public static void PrepareAndSend(string text,Func<bool> recipientMatches,Func<string> readDraft,Action focus,Action<string> write,Action check,Action send){
   PrepareAndSend(text,recipientMatches,readDraft,focus,write,check,send,null);
  }
  public static void PrepareAndSend(string text,Func<bool> recipientMatches,Func<string> readDraft,Action focus,Action<string> write,Action check,Action send,Action<string> preserveDraft){
   text=ValidateMessage(text);check();
   if(!recipientMatches())throw new Exception("Nao confirmei o contato. Nada foi enviado.");
   string previous=NormalizeDraft(readDraft());
   if(previous.Length>0&&previous!=text){if(preserveDraft==null)throw new Exception("O rascunho anterior precisa ser preservado antes de substituir o texto.");preserveDraft(previous);}
   focus();check();
   if(NormalizeDraft(readDraft())!=previous)throw new Exception("O rascunho mudou enquanto eu preparava o envio. Preservei o texto e parei a acao.");
   if(previous!=text)write(text);check();
   var draftDeadline=DateTime.UtcNow.AddSeconds(3);
   while(readDraft()!=text){check();if(DateTime.UtcNow>=draftDeadline)throw new Exception("O campo de mensagem nao terminou de atualizar o texto esperado. Nao pressionei Enviar; confira o rascunho.");Thread.Sleep(40);}
   if(!recipientMatches())throw new Exception("A conversa mudou durante a escrita. Nao pressionei Enviar.");
   check();send();
  }
  public static string SendChecked(AutomationElement root,string recipient,string text,string platform,CancellationToken token,Func<AutomationElement,bool> verifyRecipient,Func<AutomationElement,bool> invoke){
   text=ValidateMessage(text);Check(token);if(!verifyRecipient(root))throw new Exception("Nao confirmei a conversa privada de "+recipient+". Nada foi enviado.");
   var editors=new List<AutomationElement>();
   if(platform=="Discord"){var found=FindDiscordComposer(root,recipient,true);if(found!=null)editors.Add(found);}
   else if(platform=="WhatsApp Web"){var found=WebComposer(root);if(found!=null)editors.Add(found);}
   else foreach(AutomationElement edit in root.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Document))))if(!edit.Current.IsOffscreen&&edit.Current.IsEnabled&&IsComposer(edit.Current.Name,edit.Current.AutomationId,platform))editors.Add(edit);
   if(editors.Count!=1)throw new Exception("Nao identifiquei um unico campo de mensagem. Nada foi enviado.");
   var editor=editors[0];
   var before=MessageEvidence(root,editor,text,platform);int windowHandle=root.Current.NativeWindowHandle;
   Action focusEditor=()=>AcquireFocus(()=>OwnsFocus(editor),number=>{
    if(windowHandle!=0)root=AutomationElement.FromHandle(new IntPtr(windowHandle));
    if(!verifyRecipient(root))throw new OperationCanceledException("A conversa mudou durante a tentativa de foco. Nao pressionei Enviar.");
    if(platform=="Discord"){var fresh=FindDiscordComposer(root,recipient,true);if(fresh==null)return;editor=fresh;}
    else if(platform=="WhatsApp Web"){var fresh=WebComposer(root);if(fresh==null)return;editor=fresh;}
    try{editor.SetFocus();}catch(ElementNotAvailableException){throw;}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}
    // Focusing by mouse is a click only: never use the generic Invoke path,
    // whose Enter fallback could send an existing draft.
    if(number>0&&platform=="Discord"&&!OwnsFocus(editor))DiscordCall.TryFocusEditorByMouse(editor);
    if(number>0&&platform=="WhatsApp Web"&&!OwnsFocus(editor))ClickOnly(editor,token);
   },()=>{Check(token);if(windowHandle!=0)root=AutomationElement.FromHandle(new IntPtr(windowHandle));if(!verifyRecipient(root))throw new OperationCanceledException("A conversa mudou. Nao pressionei Enviar.");});
   PrepareAndSend(text,()=>verifyRecipient(root),()=>Text(editor),focusEditor,body=>{object value;if(platform=="WhatsApp"&&editor.TryGetCurrentPattern(ValuePattern.Pattern,out value)&&!((ValuePattern)value).Current.IsReadOnly)((ValuePattern)value).SetValue(body);else {
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
   // Never retry a send: a delayed UI update must not duplicate a message.
   var until=DateTime.UtcNow.AddSeconds(6);
   while(DateTime.UtcNow<until){
    if(token.IsCancellationRequested)break;Thread.Sleep(150);
    try{
     if(windowHandle!=0)root=AutomationElement.FromHandle(new IntPtr(windowHandle));
     if(!verifyRecipient(root))continue;
     var fresh=platform=="Discord"?FindDiscordComposer(root,recipient,true):platform=="WhatsApp Web"?WebComposer(root):editor;
     if(fresh!=null&&String.IsNullOrWhiteSpace(Text(fresh))){
      if(NewMessageAppeared(before,MessageEvidence(root,fresh,text,platform)))return "Mensagem enviada para "+recipient+" no "+platform+".";
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
    if(field.Current.IsOffscreen||!field.Current.IsEnabled||!IsComposer(field.Current.Name,field.Current.AutomationId,"WhatsApp"))continue;
    object pattern;if(!field.TryGetCurrentPattern(ValuePattern.Pattern,out pattern)&&!field.TryGetCurrentPattern(TextPattern.Pattern,out pattern))continue;
    bool wrapper=false;for(int i=matches.Count-1;i>=0;i--){if(Contains(field,matches[i])){wrapper=true;break;}if(Contains(matches[i],field))matches.RemoveAt(i);}
    if(!wrapper)matches.Add(field);
   }return matches.Count==1?matches[0]:null;
  }
  static AutomationElement WebContactPanel(AutomationElement root){
   var doc=WebDocument(root);if(doc==null)return null;
   foreach(AutomationElement area in doc.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Group),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Pane),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Window),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Custom))))if(!area.Current.IsOffscreen&&Regex.IsMatch(area.Current.Name??"",@"^(Nova conversa|New chat|Contatos no WhatsApp|Contacts on WhatsApp)$",RegexOptions.IgnoreCase))return area;
   return null;
  }
  static AutomationElement WebContactSearch(AutomationElement panel){
   var fields=new List<AutomationElement>();
   foreach(AutomationElement field in panel.FindAll(TreeScope.Descendants,InputTypes())){
    if(field.Current.IsOffscreen||!field.Current.IsKeyboardFocusable||!Regex.IsMatch(field.Current.Name??"",@"search|pesquis|buscar|nome|name|n[uú]mero|number",RegexOptions.IgnoreCase))continue;
    bool wrapper=false;for(int i=fields.Count-1;i>=0;i--){if(Contains(field,fields[i])){wrapper=true;break;}if(Contains(fields[i],field))fields.RemoveAt(i);}if(!wrapper)fields.Add(field);
   }return fields.Count==1?fields[0]:null;
  }
  static List<AutomationElement> WebContacts(AutomationElement panel,string recipient){
   var matches=new List<AutomationElement>();
   foreach(AutomationElement item in panel.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.ListItem),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.DataItem),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)))){
    if(item.Current.IsOffscreen||!ContactResult(item.Current.Name,Details(item),recipient))continue;
    bool child=false;foreach(var prior in matches)if(Contains(prior,item)){child=true;break;}if(!child)matches.Add(item);
   }return matches;
  }
  static bool ClickOnly(AutomationElement element,CancellationToken token){
   using(new Computer.PhysicalCoordinates()){
    Check(token);var bounds=element.Current.BoundingRectangle;if(element.Current.IsOffscreen||!element.Current.IsEnabled||bounds.IsEmpty||bounds.Width<3||bounds.Height<3)return false;
    var point=new System.Windows.Point(bounds.Left+bounds.Width/2,bounds.Top+bounds.Height/2);
    var hit=AutomationElement.FromPoint(point);if(hit==null||!Contains(element,hit))throw new OperationCanceledException("Outra janela cobriu o campo. Parei antes de clicar.");
    Computer.MoveSmooth((int)Math.Round(point.X),(int)Math.Round(point.Y),token);
    var after=element.Current.BoundingRectangle;if(Math.Abs(after.Left-bounds.Left)>2||Math.Abs(after.Top-bounds.Top)>2||Math.Abs(after.Width-bounds.Width)>2||Math.Abs(after.Height-bounds.Height)>2)throw new OperationCanceledException("O campo mudou de posicao. Nao cliquei.");
    hit=AutomationElement.FromPoint(point);if(hit==null||!Contains(element,hit))throw new OperationCanceledException("O campo foi coberto. Nao cliquei.");
    Computer.ClickFocusedTarget((int)Math.Round(point.X),(int)Math.Round(point.Y),token);return true;
   }
  }
  static bool WebInvoke(AutomationElement element,CancellationToken token){object pattern;Check(token);if(element.TryGetCurrentPattern(InvokePattern.Pattern,out pattern)){((InvokePattern)pattern).Invoke();return true;}return ClickOnly(element,token);}
  static bool WebHeader(AutomationElement root,string recipient){
   var doc=WebDocument(root);var composer=WebComposer(root);if(doc==null||composer==null)return false;
   var page=doc.Current.BoundingRectangle;var input=composer.Current.BoundingRectangle;bool found=false;
   foreach(AutomationElement item in doc.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)))){
    if(item.Current.IsOffscreen)continue;var rect=item.Current.BoundingRectangle;if(rect.IsEmpty||rect.Top>page.Top+160||rect.Left<input.Left-120)continue;
    string label=item.Current.Name??"";if(Regex.IsMatch(label,@"group info|dados do grupo|informa[cç][oõ]es do grupo",RegexOptions.IgnoreCase))return false;
    if(DiscordCall.ExactName(label,recipient))found=true;
   }return found;
  }
  public static Task<string> SendWhatsAppWeb(string recipient,string message,string chrome,CancellationToken token){return Task.Run(()=>{
   using(new Computer.PhysicalCoordinates()){
    string stage="abrir WhatsApp Web";
    try{
     message=ValidateMessage(message);if(String.IsNullOrWhiteSpace(recipient)||recipient.Length>100||Regex.IsMatch(recipient,@"[\x00-\x1F]"))throw new Exception("Informe o nome do contato salvo no WhatsApp.");
     var root=WebRoot();if(root==null)Process.Start(new ProcessStartInfo(chrome,"--new-window https://web.whatsapp.com/"){UseShellExecute=true});
     var until=DateTime.UtcNow.AddSeconds(20);while(root==null&&DateTime.UtcNow<until){token.ThrowIfCancellationRequested();Thread.Sleep(200);root=WebRoot();}
     if(root==null)throw new Exception("Nao consegui acessar web.whatsapp.com no Chrome. Abra o site e entre na sua conta.");
     Computer.FocusHandle(root.Current.NativeWindowHandle);stage="abrir contatos";AutomationElement panel=null;bool requested=false;until=DateTime.UtcNow.AddSeconds(12);
     while(panel==null&&DateTime.UtcNow<until){
      Check(token);var doc=WebDocument(root);if(doc==null)throw new Exception("A aba saiu do WhatsApp Web. Nada foi enviado.");
      if(!requested){foreach(AutomationElement button in doc.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)))if(!button.Current.IsOffscreen&&Regex.IsMatch(button.Current.Name??"",@"^(Nova conversa|New chat)(?:\s*\(|\s+Ctrl|$)",RegexOptions.IgnoreCase)){requested=WebInvoke(button,token);break;}}
      panel=WebContactPanel(root);
      if(panel==null)Thread.Sleep(150);
     }
     if(panel==null)throw new Exception("O WhatsApp Web nao mostrou a lista de contatos. Confira se a conta esta conectada no Chrome.");
     stage="buscar contato";var search=WebContactSearch(panel);
     if(search==null)throw new Exception("Nao identifiquei uma busca unica de contatos no WhatsApp Web.");
     AcquireFocus(()=>OwnsFocus(search),attempt=>{search.SetFocus();if(attempt>0&&!OwnsFocus(search))ClickOnly(search,token);},()=>Check(token));
     Computer.Press(65,true,false,false);if(!OwnsFocus(search))throw new OperationCanceledException("O foco saiu da busca. Nada foi enviado.");Computer.Type(recipient);
     bool selected=false;until=DateTime.UtcNow.AddSeconds(8);
     while(!selected&&DateTime.UtcNow<until){
      Check(token);List<AutomationElement> matches;
      try{panel=WebContactPanel(root);if(panel==null){Thread.Sleep(150);continue;}matches=WebContacts(panel,recipient);}catch(ElementNotAvailableException){Thread.Sleep(150);continue;}
      if(matches.Count>1)throw new Exception("Ha mais de um contato chamado "+recipient+". Use o nome completo salvo na agenda.");
      if(matches.Count==1)selected=WebInvoke(matches[0],token);if(!selected)Thread.Sleep(150);
     }
     if(!selected)throw new Exception("Nao encontrei um contato unico chamado "+recipient+" no WhatsApp Web.");
     stage="verificar conversa";until=DateTime.UtcNow.AddSeconds(8);
     while(DateTime.UtcNow<until){Check(token);if(WebHeader(root,recipient)){stage="enviar mensagem";return SendChecked(root,recipient,message,"WhatsApp Web",token,current=>WebHeader(current,recipient),button=>WebInvoke(button,token));}Thread.Sleep(150);}
     throw new Exception("Nao identifiquei o contato e o campo de mensagem na conversa do WhatsApp Web. Nada foi enviado.");
    }catch(OperationCanceledException){throw;}catch(Exception error){if(String.IsNullOrWhiteSpace(error.GetBaseException().Message))throw new Exception("O WhatsApp Web mudou os controles na etapa: "+stage+". Confira a conversa antes de repetir.");throw;}
   }
  },token);}
  public static bool ContactResult(string label,string[] details,string recipient){
   if(Regex.IsMatch(String.Join(" ",details),@"\b(group|grupo|community|comunidade)\b",RegexOptions.IgnoreCase))return false;
   if(DiscordCall.ExactName(label,recipient))return true;return details.Length>1&&DiscordCall.ExactName(details[1],recipient);
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
