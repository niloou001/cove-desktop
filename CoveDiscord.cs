using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Automation;
namespace CoveApp {
 public static class DiscordCall {
  [ThreadStatic] static bool mouseNavigation;
  [ThreadStatic] static CancellationToken mouseCancellation;
  [ThreadStatic] static bool mouseHasPosition,mouseOwnsTarget;
  [ThreadStatic] static Computer.DesktopPoint mouseLastPosition;
  sealed class MouseSession : IDisposable {
   readonly bool previous,previousHasPosition,previousOwnsTarget;readonly Computer.DesktopPoint previousPosition;readonly CancellationToken previousToken;readonly IDisposable coordinates;
   public MouseSession(CancellationToken token){previous=mouseNavigation;previousToken=mouseCancellation;previousHasPosition=mouseHasPosition;previousPosition=mouseLastPosition;previousOwnsTarget=mouseOwnsTarget;coordinates=new Computer.PhysicalCoordinates();mouseNavigation=true;mouseCancellation=token;mouseHasPosition=false;mouseOwnsTarget=false;}
   public void Dispose(){mouseNavigation=previous;mouseCancellation=previousToken;mouseHasPosition=previousHasPosition;mouseLastPosition=previousPosition;mouseOwnsTarget=previousOwnsTarget;coordinates.Dispose();}
  }
  public static IDisposable BeginMouseNavigation(CancellationToken token){return new MouseSession(token);}
  public static bool IsJoinButton(string name){return Regex.IsMatch(name??"",@"^(Entrar na chamada|Entrar no canal de voz|Entrar no canal|Conectar ao canal de voz|Join Voice|Join Call|Join Channel)$",RegexOptions.IgnoreCase);}
  public static bool IsVoiceChannel(string label,string channel){return !String.IsNullOrWhiteSpace(channel)&&Regex.IsMatch(label??"",@"^"+Regex.Escape(channel)+@"(?:\s*[,(:]).*(?:voice|voz)",RegexOptions.IgnoreCase);}
  static string Normalize(string value){var b=new StringBuilder();foreach(char c in (value??"").Normalize(NormalizationForm.FormD)){if(CharUnicodeInfo.GetUnicodeCategory(c)==UnicodeCategory.NonSpacingMark)continue;b.Append(Char.IsLetterOrDigit(c)?Char.ToLowerInvariant(c):' ');}return Regex.Replace(b.ToString(),@"\s+"," ").Trim();}
  public static bool ExactName(string label,string name){
   string expected=Normalize(name);if(expected.Length==0)return false;
   foreach(string line in (label??"").Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries)){
    string plain=Normalize(line);if(plain==expected)return true;
    string head=Regex.Split(line,@"\s*[,(:]\s*",RegexOptions.None)[0];
    if(Normalize(head)==expected)return true;
   }return false;
  }
  static string ConversationalName(string value){
   value=Normalize(value);
   value=Regex.Replace(value,@"^\d+\s+","");
   value=Regex.Replace(value,@"^(?:(?:o|a|os|as|do|da|dos|das|no|na)\s+)?(?:(?:servidor|server|call|canal de voz|canal|sala)\s+)?(?:(?:o|a|os|as|do|da|dos|das)\s+)?","");
   return Regex.Replace(value,@"\s+(mesmo|mesma)$","").Trim();
  }
  public static int NameScore(string label,string name){
   string desired=Normalize(name);if(desired.Length==0)return -1;
   string first=(label??"").Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries).Length>0?(label??"").Split(new[]{'\r','\n'},StringSplitOptions.RemoveEmptyEntries)[0]:"";
   if(Normalize(first)==desired)return 0;
   string head=Regex.Split(first,@"\s*[,(:/|]\s*")[0];
   if(Normalize(head)==desired)return 0;
   string wanted=ConversationalName(name);
   return wanted.Length>0&&(ConversationalName(first)==wanted||ConversationalName(head)==wanted)?1:-1;
  }
  public static int DestinationScore(string label,string[] details,string server,string channel,bool isServer){
   if(!isServer&&!String.IsNullOrWhiteSpace(server)&&Normalize(label)==Normalize(channel+" / "+server))return 0;
   string primary=String.IsNullOrWhiteSpace(label)&&details.Length>0?details[0]:label;
   int desiredScore=NameScore(primary,isServer?server:channel);
   if(desiredScore<0)return -1;
   if(isServer||String.IsNullOrWhiteSpace(server))return desiredScore;
   if(ConversationalName(server)==ConversationalName(channel))return -1;
   int serverScore=Int32.MaxValue;
   foreach(string item in details){
    if(Normalize(item)==Normalize(channel+" / "+server))serverScore=0;
    else {int score=NameScore(item,server);if(score>=0)serverScore=Math.Min(serverScore,score);}
   }
   return serverScore==Int32.MaxValue?-1:desiredScore*2+serverScore;
  }
  public static bool DestinationMatches(string label,string[] details,string server,string channel,bool isServer){
   return DestinationScore(label,details,server,channel,isServer)>=0;
  }
  static string Executable(){
   foreach(var p in Process.GetProcessesByName("Discord")){using(p){try{string path=p.MainModule.FileName;if(Path.GetFileName(path).Equals("Discord.exe",StringComparison.OrdinalIgnoreCase))return path;}catch{}}}
   string root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"Discord");
   if(Directory.Exists(root)){var folders=new List<string>(Directory.GetDirectories(root,"app-*"));folders.Sort((a,b)=>Directory.GetLastWriteTimeUtc(b).CompareTo(Directory.GetLastWriteTimeUtc(a)));foreach(string folder in folders){string path=Path.Combine(folder,"Discord.exe");if(File.Exists(path))return path;}}
   throw new Exception("Nao encontrei o Discord Desktop instalado.");
  }
  static AutomationElement Root(){foreach(var p in Process.GetProcessesByName("Discord")){using(p){try{if(p.MainWindowHandle!=IntPtr.Zero)return AutomationElement.FromHandle(p.MainWindowHandle);}catch{}}}return null;}
  static void CheckMouseInterference(){
   Computer.CheckMouseCancel(mouseCancellation);if(mouseOwnsTarget)Computer.RequireTargetForeground();
   if(mouseHasPosition){var now=Computer.Position();if(Math.Abs((long)now.X-mouseLastPosition.X)>4||Math.Abs((long)now.Y-mouseLastPosition.Y)>4)throw new OperationCanceledException("Voce moveu o mouse. Acao interrompida.");}
  }
  static void Pause(CancellationToken token,int milliseconds){
   if(!mouseNavigation){if(token.WaitHandle.WaitOne(milliseconds))token.ThrowIfCancellationRequested();return;}
   for(int elapsed=0;elapsed<milliseconds;elapsed+=30){CheckMouseInterference();if(token.WaitHandle.WaitOne(Math.Min(30,milliseconds-elapsed)))token.ThrowIfCancellationRequested();}
  }
  static AutomationElement FreshWindow(IntPtr handle){if(handle==IntPtr.Zero)throw new ElementNotAvailableException();return AutomationElement.FromHandle(handle);}
  static bool Stale(Exception error){return error is ElementNotAvailableException||(error is System.Runtime.InteropServices.COMException&&error.HResult==unchecked((int)0x80040201));}
  static string[] Details(AutomationElement element){var values=new List<string>{element.Current.Name??""};var texts=element.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Text));foreach(AutomationElement text in texts)if(!text.Current.IsOffscreen&&!String.IsNullOrWhiteSpace(text.Current.Name))values.Add(text.Current.Name);return values.ToArray();}
  static bool Pattern(AutomationElement element,AutomationPattern kind,out object pattern){try{return element.TryGetCurrentPattern(kind,out pattern);}catch(System.Runtime.InteropServices.COMException){pattern=null;return false;}catch(InvalidOperationException){pattern=null;return false;}}
  static bool Invoke(AutomationElement element){
   if(mouseNavigation)return ClickWithMouse(element);
   object pattern;if(!element.Current.IsEnabled)return false;
   if(element.Current.IsOffscreen&&Pattern(element,ScrollItemPattern.Pattern,out pattern)){try{((ScrollItemPattern)pattern).ScrollIntoView();}catch(System.Runtime.InteropServices.COMException){}}
   if(element.Current.IsOffscreen)return false;
   if(Pattern(element,InvokePattern.Pattern,out pattern)){try{((InvokePattern)pattern).Invoke();return true;}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}}
   if(Pattern(element,SelectionItemPattern.Pattern,out pattern)){try{((SelectionItemPattern)pattern).Select();element.SetFocus();Computer.Press(13,false,false,false);return true;}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}}
   try{element.SetFocus();var focused=AutomationElement.FocusedElement;if(focused!=null&&Automation.Compare(focused,element)){Computer.Press(13,false,false,false);return true;}}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}
   // Some Chromium controls expose geometry but no default action. Verify the
   // exact element under the pointer before clicking its visible bounds.
   var bounds=element.Current.BoundingRectangle;if(bounds.IsEmpty||bounds.Width<2||bounds.Height<2)return false;
   var point=new System.Windows.Point(bounds.Left+bounds.Width/2,bounds.Top+bounds.Height/2);
   var hit=AutomationElement.FromPoint(point);bool verified=false;
   for(int n=0;n<8&&hit!=null;n++){if(Automation.Compare(hit,element)){verified=true;break;}hit=TreeWalker.ControlViewWalker.GetParent(hit);}
   if(!verified)return false;Computer.Move((int)point.X,(int)point.Y);Computer.Click(false,false);return true;
  }
  static bool HitTarget(AutomationElement element,System.Windows.Point point){
   var hit=AutomationElement.FromPoint(point);
   if(hit==null||hit.Current.ProcessId!=element.Current.ProcessId)return false;
   for(int n=0;n<10&&hit!=null;n++){if(Automation.Compare(hit,element))return true;hit=TreeWalker.ControlViewWalker.GetParent(hit);}return false;
  }
  static bool ClickWithMouse(AutomationElement element){
   CheckMouseInterference();if(!mouseOwnsTarget){Computer.PrepareTargetMouse();mouseOwnsTarget=true;}object pattern;
   if(!element.Current.IsEnabled)throw new Exception("O controle do Discord esta desabilitado.");
   if(element.Current.IsOffscreen&&Pattern(element,ScrollItemPattern.Pattern,out pattern)){((ScrollItemPattern)pattern).ScrollIntoView();Pause(mouseCancellation,100);}
   if(element.Current.IsOffscreen)return false;
   var before=element.Current.BoundingRectangle;
   if(before.IsEmpty||before.Width<2||before.Height<2)return false;
   var point=new System.Windows.Point(before.Left+before.Width/2,before.Top+before.Height/2);
   if(!HitTarget(element,point))throw new OperationCanceledException("Outra janela esta cobrindo o alvo no Discord. Parei antes de clicar.");
   Computer.MoveSmooth((int)Math.Round(point.X),(int)Math.Round(point.Y),mouseCancellation);
   var after=element.Current.BoundingRectangle;
   if(Math.Abs(after.Left-before.Left)>2||Math.Abs(after.Top-before.Top)>2||Math.Abs(after.Width-before.Width)>2||Math.Abs(after.Height-before.Height)>2)throw new OperationCanceledException("O Discord mudou de posicao durante o movimento. Nao cliquei.");
   if(!HitTarget(element,point))throw new OperationCanceledException("O alvo ficou coberto durante o movimento. Nao cliquei.");
   Computer.ClickFocusedTarget((int)Math.Round(point.X),(int)Math.Round(point.Y),mouseCancellation);mouseLastPosition=Computer.Position();mouseHasPosition=true;Pause(mouseCancellation,100);return true;
  }
  public static bool TryFocusEditorByMouse(AutomationElement editor){return mouseNavigation&&ClickWithMouse(editor);}
  public static string DiagnosticFile;
  static bool ServerNavigation(string name,string id){
   return Regex.IsMatch(name??"",@"^(Servers(?: sidebar| list)?|Servidores|Lista de servidores|Barra lateral (?:de|dos) servidores)$",RegexOptions.IgnoreCase)||(id??"").IndexOf("guildsnav",StringComparison.OrdinalIgnoreCase)>=0;
  }
  public static bool ChannelNavigation(string name,string id,string server){
   if(Regex.IsMatch(id??"",@"^(channels|channelsnav|channel-list|channels-list)(?:$|[-_])",RegexOptions.IgnoreCase))return true;
   if(Regex.IsMatch(name??"",@"^(Channels(?: and roles)?|Canais(?: e cargos)?|Server channels|Canais do servidor(?: .+)?)$",RegexOptions.IgnoreCase))return true;
   return !String.IsNullOrWhiteSpace(server)&&Regex.IsMatch(name??"",@"\b(server|servidor)\b",RegexOptions.IgnoreCase)&&NameScore(name,server)>=0;
  }
  static Condition Containers(){return new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Tree),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.List),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Pane),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Group));}
  static Condition Items(){return new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.TreeItem),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.ListItem),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Hyperlink),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button));}
  public static int VoiceChannelScore(string label,string help,string itemType,string id,string channel){
   string metadata=(label??"")+" "+(help??"")+" "+(itemType??"")+" "+(id??"");
   if(Regex.IsMatch(metadata,@"\b(text channel|canal de texto)\b",RegexOptions.IgnoreCase))return -1;
   if(!Regex.IsMatch(metadata,@"\b(voice channel|canal de voz|canal por voz)\b|voice[-_]?channel",RegexOptions.IgnoreCase))return -1;
   string primary=Regex.Replace(label??"",@"^(voice channel|canal de voz|canal por voz)\s*[:, -]?\s*","",RegexOptions.IgnoreCase);
   return NameScore(primary,channel);
  }
  static void ScrollTop(AutomationElement nav){try{object pattern;if(Pattern(nav,ScrollPattern.Pattern,out pattern)&&((ScrollPattern)pattern).Current.VerticallyScrollable)((ScrollPattern)pattern).SetScrollPercent(ScrollPattern.NoScroll,0);}catch(System.Runtime.InteropServices.COMException){}catch(InvalidOperationException){}}
  static bool ScrollMore(AutomationElement nav){try{object pattern;if(!Pattern(nav,ScrollPattern.Pattern,out pattern))return false;var scroll=(ScrollPattern)pattern;if(!scroll.Current.VerticallyScrollable||scroll.Current.VerticalScrollPercent>=99.9)return false;double before=scroll.Current.VerticalScrollPercent;scroll.Scroll(ScrollAmount.NoAmount,ScrollAmount.LargeIncrement);return scroll.Current.VerticalScrollPercent!=before;}catch(System.Runtime.InteropServices.COMException){return false;}catch(InvalidOperationException){return false;}}
  public static bool TitleContainsDestination(string title,string name){foreach(string part in Regex.Split(title??"",@"\s+[-\u2013\u2014]\s+|[|]"))if(NameScore(part.Trim(),name)>=0)return true;return false;}
  static bool Selected(AutomationElement item){try{object pattern;return item.TryGetCurrentPattern(SelectionItemPattern.Pattern,out pattern)&&((SelectionItemPattern)pattern).Current.IsSelected;}catch(ElementNotAvailableException){return false;}catch(System.Runtime.InteropServices.COMException){return false;}}
  public static bool IsOpenServerView(string label,string server){return !String.IsNullOrWhiteSpace(server)&&NameScore(label,server)>=0&&Regex.IsMatch(label??"",@"[,(]\s*(server|servidor)\s*[),]?",RegexOptions.IgnoreCase);}
  public static bool IsServerFolder(string label){return Regex.IsMatch(label??"",@"(?:^|[,()])\s*(pasta|folder)\s*(?:[,()]|$)",RegexOptions.IgnoreCase);}
  static bool CurrentServer(AutomationElement root,string server){
   var exact=root.FindFirst(TreeScope.Descendants,new AndCondition(Containers(),new OrCondition(
    new PropertyCondition(AutomationElement.NameProperty,server+" (servidor)",PropertyConditionFlags.IgnoreCase),
    new PropertyCondition(AutomationElement.NameProperty,server+" (server)",PropertyConditionFlags.IgnoreCase))));
   if(exact!=null&&!exact.Current.IsOffscreen)return true;
   var containers=root.FindAll(TreeScope.Descendants,Containers());
   foreach(AutomationElement nav in containers){try{if(!nav.Current.IsOffscreen&&IsOpenServerView(nav.Current.Name,server))return true;}catch(ElementNotAvailableException){}catch(System.Runtime.InteropServices.COMException){}}
   return false;
  }
  static bool ServerConfirmed(AutomationElement root,AutomationElement item,string server){
   if(CurrentServer(root,server)||Selected(item)||TitleContainsDestination(root.Current.Name,server))return true;
   var containers=root.FindAll(TreeScope.Descendants,Containers());
   foreach(AutomationElement nav in containers)if(ChannelNavigation(nav.Current.Name,nav.Current.AutomationId,server)&&NameScore(nav.Current.Name,server)>=0)return true;
   return false;
  }
  static bool ConfirmServer(IntPtr handle,string server,CancellationToken token){
   var until=DateTime.UtcNow.AddSeconds(5);
   while(DateTime.UtcNow<until){
    Pause(token,150);
    try{var root=FreshWindow(handle);if(CurrentServer(root,server)||TitleContainsDestination(root.Current.Name,server)){Pause(token,250);return true;}}
    catch(Exception error){if(!Stale(error))throw;}
   }
   return false;
  }
  static bool SelectServer(AutomationElement root,string server,CancellationToken token){
   IntPtr handle=new IntPtr(root.Current.NativeWindowHandle);
   foreach(AutomationElement nav in root.FindAll(TreeScope.Descendants,Containers()))if(ServerNavigation(nav.Current.Name,nav.Current.AutomationId))ScrollTop(nav);
   var openedFolders=new HashSet<string>(StringComparer.Ordinal);var until=DateTime.UtcNow.AddSeconds(15);var settleUntil=DateTime.UtcNow.AddMilliseconds(1200);int unavailable=0;
   while(DateTime.UtcNow<until){
    token.ThrowIfCancellationRequested();bool changed=false;
    try{
     root=FreshWindow(handle);if(CurrentServer(root,server))return true;
     var containers=root.FindAll(TreeScope.Descendants,Containers());
     foreach(AutomationElement nav in containers){
      if(!ServerNavigation(nav.Current.Name,nav.Current.AutomationId))continue;
      // Take a read-only snapshot. Nothing is expanded before a matching
      // server has been examined; an expansion invalidates the whole snapshot.
      var items=nav.FindAll(TreeScope.Descendants,Items());var matches=new List<AutomationElement>();var folders=new List<AutomationElement>();int best=Int32.MaxValue;
      foreach(AutomationElement item in items){
       object pattern;
       if(IsServerFolder(item.Current.Name)||(Pattern(item,ExpandCollapsePattern.Pattern,out pattern)&&((ExpandCollapsePattern)pattern).Current.ExpandCollapseState!=ExpandCollapseState.LeafNode)){folders.Add(item);continue;}
       int score=NameScore(item.Current.Name,server);if(score<0||score>best)continue;if(score<best){best=score;matches.Clear();}matches.Add(item);
      }
      if(matches.Count>1)throw new Exception("Encontrei mais de um servidor com esse nome. Qual deles voce quer?");
      if(matches.Count==1&&Invoke(matches[0])){
       if(ConfirmServer(handle,server,token))return true;
       throw new Exception("Acionei o servidor "+server+", mas nao consegui confirmar sua selecao. Nao vou clicar em um canal de outro servidor.");
      }
      foreach(AutomationElement folder in folders){
       string key=folder.Current.Name??"";if(openedFolders.Contains(key))continue;object pattern;
       if(Pattern(folder,ExpandCollapsePattern.Pattern,out pattern)){
        var expandable=(ExpandCollapsePattern)pattern;if(expandable.Current.ExpandCollapseState!=ExpandCollapseState.Collapsed)continue;
        openedFolders.Add(key);if(mouseNavigation){if(!Invoke(folder))continue;}else expandable.Expand();changed=true;break;
       }
       if(IsServerFolder(key)){openedFolders.Add(key);if(Invoke(folder)){changed=true;break;}}
      }
      if(changed)break;
      if(ScrollMore(nav)){changed=true;break;}
     }
     if(!changed){if(DateTime.UtcNow<settleUntil){Pause(token,150);continue;}return false;}
     // Reacquire the window, navigation containers and items on the next pass.
     settleUntil=DateTime.UtcNow.AddMilliseconds(1200);Pause(token,150);unavailable=0;
    }catch(Exception error){if(!Stale(error))throw;if(++unavailable>8)throw;Pause(token,150);}
   }
   throw new Exception("A lista de servidores do Discord continuou mudando e nao consegui concluir a selecao.");
  }
  static AutomationElement SelectVoiceChannel(AutomationElement root,string server,string channel,CancellationToken token){
   IntPtr handle=new IntPtr(root.Current.NativeWindowHandle);var until=DateTime.UtcNow.AddSeconds(12);var settleUntil=DateTime.UtcNow.AddMilliseconds(1200);int unavailable=0;
   foreach(AutomationElement nav in root.FindAll(TreeScope.Descendants,Containers()))if(ChannelNavigation(nav.Current.Name,nav.Current.AutomationId,server))ScrollTop(nav);
   var openedCategories=new HashSet<string>(StringComparer.Ordinal);
   while(DateTime.UtcNow<until){
    token.ThrowIfCancellationRequested();bool changed=false;
    try{
     root=FreshWindow(handle);var containers=root.FindAll(TreeScope.Descendants,Containers());
     foreach(AutomationElement nav in containers){
      if(!ChannelNavigation(nav.Current.Name,nav.Current.AutomationId,server))continue;
      var items=nav.FindAll(TreeScope.Descendants,Items());var matches=new List<AutomationElement>();var categories=new List<AutomationElement>();int best=Int32.MaxValue;
      foreach(AutomationElement item in items){
       int score=VoiceChannelScore(item.Current.Name,item.Current.HelpText,item.Current.ItemType,item.Current.AutomationId,channel);
       if(score>=0){if(score>best)continue;if(score<best){matches.Clear();best=score;}matches.Add(item);continue;}
       object pattern;if(Pattern(item,ExpandCollapsePattern.Pattern,out pattern)&&((ExpandCollapsePattern)pattern).Current.ExpandCollapseState==ExpandCollapseState.Collapsed)categories.Add(item);
      }
      if(matches.Count>1)throw new Exception("Encontrei duas calls com esse nome no servidor. Preciso saber qual delas voce quer.");
      if(matches.Count==1&&Invoke(matches[0])){Pause(token,250);return matches[0];}
      foreach(AutomationElement category in categories){
       string key=category.Current.Name??"";if(openedCategories.Contains(key))continue;object pattern;
       if(Pattern(category,ExpandCollapsePattern.Pattern,out pattern)){openedCategories.Add(key);if(mouseNavigation){if(!Invoke(category))continue;}else ((ExpandCollapsePattern)pattern).Expand();changed=true;break;}
      }
      if(changed)break;
      if(ScrollMore(nav)){changed=true;break;}
     }
     if(!changed){if(DateTime.UtcNow<settleUntil){Pause(token,150);continue;}break;}settleUntil=DateTime.UtcNow.AddMilliseconds(1200);Pause(token,150);unavailable=0;
    }catch(Exception error){if(!Stale(error))throw;if(++unavailable>8)throw;Pause(token,150);}
   }
   throw new Exception("Nao consegui localizar a call "+channel+" na lista de canais do servidor "+server+". Nao usei a pesquisa do Discord.");
  }
  static string SingleLine(string value){value=(value??"").Replace("\r"," ").Replace("\n"," ").Replace("\t"," ");return value.Length>160?value.Substring(0,160):value;}
  static AutomationElement SelectLinkedVoiceChannel(AutomationElement root,string server,string channel,CancellationToken token){
   IntPtr handle=new IntPtr(root.Current.NativeWindowHandle);var until=DateTime.UtcNow.AddSeconds(3);
   while(DateTime.UtcNow<until){
    token.ThrowIfCancellationRequested();
    try{
     root=FreshWindow(handle);
     if(Connected(root,server,channel))return null;
     if(!String.IsNullOrWhiteSpace(server)&&!CurrentServer(root,server)&&!TitleContainsDestination(root.Current.Name,server)){Pause(token,150);continue;}
     if(TitleContainsDestination(root.Current.Name,channel)){
      var buttons=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button));var matches=new List<AutomationElement>();
      foreach(AutomationElement button in buttons)if(!button.Current.IsOffscreen&&IsJoinButton(button.Current.Name))matches.Add(button);
      if(matches.Count==1&&Invoke(matches[0]))return matches[0];
     }
     // The link has already selected the guild. Do not enumerate its folders.
     return SelectVoiceChannel(root,server,channel,token);
    }catch(Exception error){if(!Stale(error))throw;Pause(token,150);}
   }
   throw new Exception("Abri o link, mas o Discord nao mostrou os controles do canal esperado. Confira o login e o acesso ao canal.");
  }
  static void Diagnose(AutomationElement root,string server,string channel,string stage,Exception error){
   if(String.IsNullOrWhiteSpace(DiagnosticFile))return;
   try{
    var log=new StringBuilder("Cove Discord direct-navigation-v5-inputs\n");log.AppendLine(DateTime.UtcNow.ToString("o"));log.AppendLine("Modo: "+(mouseNavigation?"mouse":"controles/link"));log.AppendLine("Etapa: "+SingleLine(stage));log.AppendLine("Servidor: "+SingleLine(server));log.AppendLine("Canal: "+SingleLine(channel));log.AppendLine("Erro: "+error.GetType().FullName+" (0x"+error.HResult.ToString("X8")+") "+SingleLine(error.Message));
    File.WriteAllText(DiagnosticFile,log.ToString(),Encoding.UTF8);
    foreach(var display in Computer.Displays())log.AppendLine("Monitor: "+display.Left+","+display.Top+","+display.Right+","+display.Bottom);
    if(root!=null){
     log.AppendLine("Pilha: "+SingleLine(error.StackTrace));
     if(server=="privado"){try{log.Append(Messaging.DescribeDiscordInputs(root));}catch(Exception snapshotError){log.AppendLine("Leitura dos campos indisponivel: "+snapshotError.GetType().Name);}File.WriteAllText(DiagnosticFile,log.ToString(),Encoding.UTF8);return;}
     var containers=root.FindAll(TreeScope.Descendants,Containers());
     foreach(AutomationElement nav in containers){if(!ServerNavigation(nav.Current.Name,nav.Current.AutomationId)&&!ChannelNavigation(nav.Current.Name,nav.Current.AutomationId,server))continue;
      log.AppendLine("Navegacao: "+SingleLine(nav.Current.Name)+" | "+SingleLine(nav.Current.AutomationId)+" | "+nav.Current.ControlType.ProgrammaticName);
      var items=nav.FindAll(TreeScope.Descendants,Items());int count=0;foreach(AutomationElement item in items){if(count++>=100)break;log.AppendLine("  "+SingleLine(item.Current.Name)+" | "+SingleLine(item.Current.AutomationId)+" | "+SingleLine(item.Current.HelpText));}
     }
    }
    File.WriteAllText(DiagnosticFile,log.ToString(),Encoding.UTF8);
   }catch{}
  }
  static bool Connected(AutomationElement root,string server,string channel){
   var buttons=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button));
   foreach(AutomationElement b in buttons){if(b.Current.IsOffscreen||!Regex.IsMatch(b.Current.Name??"",@"^(Disconnect|Desconectar)(?:\s|$)",RegexOptions.IgnoreCase))continue;
    var panel=TreeWalker.ControlViewWalker.GetParent(b);for(int n=0;n<3&&panel!=null;n++){
     if(Automation.Compare(panel,root)||panel.Current.BoundingRectangle.Height>root.Current.BoundingRectangle.Height*0.45)break;
    var details=Details(panel);bool foundChannel=false,foundServer=String.IsNullOrEmpty(server);
     foreach(string value in details){if(NameScore(value,channel)>=0)foundChannel=true;if(ConversationalName(server)!=ConversationalName(channel)&&NameScore(value,server)>=0)foundServer=true;if(Normalize(value)==Normalize(channel+" / "+server)){foundChannel=true;foundServer=true;}}
     if(foundChannel&&foundServer)return true;panel=TreeWalker.ControlViewWalker.GetParent(panel);
    }
   }return false;
  }
  public static Task<string> Join(string url,string channel,CancellationToken token){return Join(url,"",channel,token);}
  public static bool IsPrivateResult(string label,string metadata,string friend){
   return ExactName(label,friend)&&Regex.IsMatch(metadata??"",@"\b(user|usuario|usuário|direct message|mensagem direta|mensagens diretas)\b",RegexOptions.IgnoreCase)&&!Regex.IsMatch(metadata??"",@"\b(server|servidor|group|grupo)\b",RegexOptions.IgnoreCase);
  }
  public static bool IsPrivateVoiceButton(string label){return Regex.IsMatch(label??"",@"^(Start Voice Call|Start voice call|Iniciar chamada de voz|Iniciar chamada por voz|Chamada de voz)$",RegexOptions.IgnoreCase);}
  public static bool IsPickerMarker(string name,string id){return Regex.IsMatch((name??"")+" "+(id??""),@"quick.?switch|seletor r[aá]pido|alternador r[aá]pido|navega[cç][aã]o r[aá]pida",RegexOptions.IgnoreCase);}
  public static bool IsPickerSearchName(string name){return Regex.IsMatch(name??"",@"where would you like to go|para onde (?:voc[eê] (?:quer|gostaria de) |quer |gostaria de )?ir|search|pesquis|buscar",RegexOptions.IgnoreCase);}
  static AutomationElement PickerAncestor(AutomationElement field,AutomationElement root){
   var ancestor=TreeWalker.ControlViewWalker.GetParent(field);
   for(int n=0;n<10&&ancestor!=null&&!Automation.Compare(ancestor,root);n++,ancestor=TreeWalker.ControlViewWalker.GetParent(ancestor)){
    if(IsPickerMarker(ancestor.Current.Name,ancestor.Current.AutomationId))return ancestor;
    if(IsPickerSearchName(field.Current.Name)&&Regex.IsMatch(ancestor.Current.LocalizedControlType??"",@"\bdialog\b|di[aá]logo",RegexOptions.IgnoreCase))return ancestor;
   }return null;
  }
  static AutomationElement PickerField(AutomationElement root,out AutomationElement picker){
   picker=null;if(root==null)return null;
   try{var fields=root.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.ComboBox)));
   foreach(AutomationElement field in fields){
    if(field.Current.IsOffscreen||!field.Current.IsEnabled)continue;var candidate=PickerAncestor(field,root);if(candidate==null)continue;
    picker=candidate;return field;
   }return null;}catch(Exception error){if(Stale(error))return null;throw;}
  }
  static void FillPicker(AutomationElement field,string text){
   if(String.IsNullOrWhiteSpace(text)||text.Length>100||Regex.IsMatch(text,@"[\x00-\x1F]"))throw new Exception("Informe um nome de contato valido.");
   object value;if(Pattern(field,ValuePattern.Pattern,out value)&&!((ValuePattern)value).Current.IsReadOnly){((ValuePattern)value).SetValue(text);return;}
   field.SetFocus();var focused=AutomationElement.FocusedElement;
   if(!PickerFocusMatches(field,focused))throw new Exception("O campo de busca do Discord nao ficou em foco. Nao digitei na conversa.");
   Computer.Press(65,true,false,false);
   if(!PickerFocusMatches(field,AutomationElement.FocusedElement))throw new Exception("O foco saiu da busca do Discord. Nao digitei na conversa.");
   Computer.Type(text);
  }
  static bool PickerFocusMatches(AutomationElement field,AutomationElement focused){
   if(focused==null||focused.Current.ProcessId!=field.Current.ProcessId)return false;
   if(Automation.Compare(focused,field))return true;
   if(focused.Current.ControlType!=ControlType.Edit)return false;
   var parent=TreeWalker.ControlViewWalker.GetParent(focused);
   for(int n=0;n<3&&parent!=null;n++,parent=TreeWalker.ControlViewWalker.GetParent(parent))if(Automation.Compare(parent,field))return true;
   return false;
  }
  public static Task<string> CallFriend(string friend,bool useMouse,CancellationToken token){
   return PrivateAction(friend,null,useMouse,token);
  }
  public static Task<string> SendFriendMessage(string friend,string message,bool useMouse,CancellationToken token){
   return PrivateAction(friend,message,useMouse,token);
  }
  static Task<string> PrivateAction(string friend,string message,bool useMouse,CancellationToken token){
   return Task.Run(()=>{
     AutomationElement root=null;string stage="preparar controle do Discord";IDisposable session=null;
     try{
      session=useMouse?BeginMouseNavigation(token):null;stage="localizar amigo";
      if(String.IsNullOrWhiteSpace(friend)||friend.Length>100||Regex.IsMatch(friend,@"[\x00-\x1F]"))throw new Exception("Informe o nome do amigo.");
      root=Root();if(root==null)Process.Start(new ProcessStartInfo(Executable()){UseShellExecute=true});
      var until=DateTime.UtcNow.AddSeconds(12);while(root==null&&DateTime.UtcNow<until){Pause(token,200);root=Root();}
      if(root==null)throw new Exception("Nao consegui acessar a janela do Discord.");
      Computer.FocusHandle(root.Current.NativeWindowHandle);if(mouseNavigation)mouseOwnsTarget=true;
      stage="abrir seletor de conversas";
      // Wait for the scoped picker; Chromium can expose its input as a ComboBox
      // or as a textbox without ValuePattern, and focus may arrive later.
      AutomationElement picker,field=PickerField(root,out picker);
      if(field==null)Computer.Press(75,true,false,false);
      until=DateTime.UtcNow.AddSeconds(4);
      while(field==null&&DateTime.UtcNow<until){Pause(token,100);root=Root();if(root!=null)field=PickerField(root,out picker);}
      if(field==null)throw new Exception("O Discord nao abriu uma busca de conversas acessivel. Nada foi enviado nem foi iniciada uma ligacao.");
      FillPicker(field,friend);Pause(token,250);
      stage="selecionar amigo";
      bool selected=false;until=DateTime.UtcNow.AddSeconds(5);
      while(DateTime.UtcNow<until&&!selected){
       root=Root();field=PickerField(root,out picker);if(picker==null){Pause(token,150);continue;}var matches=new List<AutomationElement>();
       foreach(AutomationElement item in picker.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.ListItem),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.DataItem)))){
        if(item.Current.IsOffscreen)continue;string metadata=String.Join(" ",Details(item))+" "+item.Current.HelpText+" "+item.Current.ItemType;
        if(IsPrivateResult(item.Current.Name,metadata,friend))matches.Add(item);
       }
       if(matches.Count>1)throw new Exception("Ha mais de um amigo com esse nome. Diga o nome de usuario completo.");
       if(matches.Count==1)selected=Invoke(matches[0]);if(!selected)Pause(token,150);
      }
      if(!selected)throw new Exception("Nao identifiquei uma conversa privada unica com "+friend+". Use o nome de usuario do Discord.");
      if(message!=null){
       stage="aguardar campo de mensagem";
       root=WaitForPrivateMessage(()=>Root(),friend,token);
       stage="enviar mensagem privada";
       return Messaging.SendChecked(root,friend,message,"Discord",token,Fresh=>PrivateHeader(Fresh,friend),element=>Invoke(element));
      }
      stage="confirmar conversa privada";until=DateTime.UtcNow.AddSeconds(5);
      while(DateTime.UtcNow<until){
       Pause(token,200);root=Root();
       // Require the requested recipient in the conversation toolbar before ringing.
       var bars=PrivateHeaders(root);
       foreach(AutomationElement bar in bars){
        if(bar.Current.IsOffscreen)continue;bool recipient=ExactName(bar.Current.Name,friend);
        foreach(string detail in Details(bar))if(ExactName(detail,friend))recipient=true;
        if(!recipient)continue;
        var calls=new List<AutomationElement>();
        foreach(AutomationElement button in bar.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)))if(!button.Current.IsOffscreen&&IsPrivateVoiceButton(button.Current.Name))calls.Add(button);
        if(calls.Count!=1)continue;stage="iniciar chamada privada";
        if(Invoke(calls[0]))return "Acionei a chamada de voz para "+friend+". A outra pessoa precisa atender.";
       }
      }
      throw new Exception(message==null?"Nao encontrei o botao de voz na conversa com "+friend+". Nao iniciei a ligacao.":"O Discord nao mostrou o campo de mensagem da conversa com "+friend+". Nada foi enviado.");
     }catch(OperationCanceledException error){Diagnose(root,"privado",friend,stage,error);if(String.IsNullOrWhiteSpace(error.GetBaseException().Message))throw new OperationCanceledException("A acao no Discord foi interrompida. Confira a conversa antes de repetir.");throw;}
     catch(Exception error){Diagnose(root,"privado",friend,stage,error);if(Stale(error)||Stale(error.GetBaseException())||String.IsNullOrWhiteSpace(error.GetBaseException().Message))throw new Exception(PrivateFailureMessage(stage));throw;}
     finally{if(session!=null)session.Dispose();}
   },token);
  }
  public static string PrivateFailureMessage(string stage){
   if(stage=="enviar mensagem privada")return "Os controles do Discord mudaram durante o envio. Confira o rascunho e a conversa antes de repetir; nao repeti o envio automaticamente.";
   if(stage=="iniciar chamada privada")return "Os controles do Discord mudaram ao iniciar a ligacao. Confira a chamada no Discord antes de repetir.";
   return "Os controles do Discord mudaram na etapa: "+stage+". O envio nao foi iniciado. Tente novamente quando a conversa terminar de carregar.";
  }
  static AutomationElement WaitForPrivateMessage(Func<AutomationElement> getRoot,string friend,CancellationToken token){
   var until=DateTime.UtcNow.AddSeconds(12);string last="";int stable=0;
   while(DateTime.UtcNow<until){
    Pause(token,150);
    try{
     var root=getRoot();if(root==null||!PrivateHeader(root,friend)){stable=0;last="";continue;}
     var editor=Messaging.FindDiscordComposer(root,friend,true);if(editor==null){stable=0;last="";continue;}
     string identity=String.Join(".",Array.ConvertAll(editor.GetRuntimeId(),id=>id.ToString()));
     stable=identity==last?stable+1:1;last=identity;
     if(stable>=3)return root;
    }catch(Exception error){if(!Stale(error))throw;stable=0;last="";}
   }
   throw new Exception("A conversa com "+friend+" ainda nao mostrou um campo de mensagem estavel. Nada foi enviado. Aguarde o Discord carregar e tente novamente.");
  }
  static bool PrivateHeader(AutomationElement root,string friend){
   foreach(AutomationElement bar in PrivateHeaders(root)){
    if(bar.Current.IsOffscreen)continue;bool recipient=ExactName(bar.Current.Name,friend);
    foreach(string detail in Details(bar))if(ExactName(detail,friend))recipient=true;
    if(recipient){
     bool privateControl=false;foreach(AutomationElement button in bar.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button)))if(!button.Current.IsOffscreen&&IsPrivateVoiceButton(button.Current.Name))privateControl=true;
     if(Messaging.FindDiscordComposer(root,friend,privateControl)!=null)return true;
    }
   }return false;
  }
  static IEnumerable<AutomationElement> PrivateHeaders(AutomationElement root){
   foreach(AutomationElement element in root.FindAll(TreeScope.Descendants,new OrCondition(new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.ToolBar),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Group),new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Pane)))){
    if(element.Current.IsOffscreen)continue;
    if(element.Current.ControlType==ControlType.ToolBar||Regex.IsMatch(element.Current.Name??"",@"^(Channel header|Chat header|Conversation header|Cabe[cç]alho (?:do canal|da conversa))$",RegexOptions.IgnoreCase)||Regex.IsMatch(element.Current.AutomationId??"",@"^(channel-header|chat-header|conversation-header)(?:$|[-_])",RegexOptions.IgnoreCase))yield return element;
   }
  }
  public static Task<string> Join(string url,string server,string channel,CancellationToken token){return JoinInternal(url,server,channel,token,false);}
  public static Task<string> JoinMouse(string url,string server,string channel,CancellationToken token){return JoinInternal(url,server,channel,token,true);}
  static Task<string> JoinInternal(string url,string server,string channel,CancellationToken token,bool useMouse){
   return Task.Run(()=>{
    using(IDisposable session=useMouse?BeginMouseNavigation(token):null){
    AutomationElement root=null;string stage="abrir Discord";
    try{
     token.ThrowIfCancellationRequested();if(String.IsNullOrWhiteSpace(channel))throw new Exception("Informe o nome da call.");
     if(!String.IsNullOrEmpty(url)&&!Regex.IsMatch(url,@"^discord://-/channels/\d{15,22}/\d{15,22}$"))throw new Exception("Link de canal invalido.");
     root=Root();string exe=Executable();if(root==null||root.Current.IsOffscreen||!String.IsNullOrEmpty(url))Process.Start(new ProcessStartInfo(exe,String.IsNullOrEmpty(url)?"":"--url \""+url+"\""){UseShellExecute=true});
     var deadline=DateTime.UtcNow.AddSeconds(12);while(root==null&&DateTime.UtcNow<deadline){Pause(token,200);root=Root();}
     if(root==null)throw new Exception("Nao consegui acessar a janela do Discord nesta sessao do Windows.");
     Computer.FocusHandle(root.Current.NativeWindowHandle);
     if(mouseNavigation)mouseOwnsTarget=true;
     AutomationElement selected;
     if(!String.IsNullOrEmpty(url)){
      stage="abrir canal pelo link";var linkedUntil=DateTime.UtcNow.AddSeconds(8);selected=null;bool ready=false;
      Pause(token,750);
      while(DateTime.UtcNow<linkedUntil){
       token.ThrowIfCancellationRequested();
       try{root=Root();if(root!=null&&(String.IsNullOrEmpty(server)||CurrentServer(root,server)||TitleContainsDestination(root.Current.Name,server))){ready=true;break;}}catch(Exception error){if(!Stale(error))throw;}
       Pause(token,200);
      }
      if(!ready)throw new Exception("O link foi aberto, mas o Discord nao mostrou o servidor esperado. Confira o login e o acesso ao canal.");
      selected=SelectLinkedVoiceChannel(root,server,channel,token);
      if(selected==null)return "Conectado a call "+channel+(String.IsNullOrEmpty(server)?"":" no servidor "+server)+".";
     }else{
      stage="selecionar servidor";
      if(!String.IsNullOrWhiteSpace(server)&&!SelectServer(root,server,token))throw new Exception("Nao consegui localizar o servidor "+server+" na lista de servidores acessivel do Discord. Nao usei a pesquisa.");
      stage="selecionar canal de voz";selected=SelectVoiceChannel(root,server,channel,token);
     }
     stage="confirmar conexao";deadline=DateTime.UtcNow.AddSeconds(4);bool joined=false;
     while(DateTime.UtcNow<deadline){
      Pause(token,250);
      try{
       root=Root();if(root==null)continue;
       if(Connected(root,server,channel))return "Conectado a call "+channel+(String.IsNullOrEmpty(server)?"":" no servidor "+server)+".";
       if(!joined&&(TitleContainsDestination(root.Current.Name,channel)||Selected(selected))){
        var buttons=root.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button));var joinButtons=new List<AutomationElement>();foreach(AutomationElement button in buttons)if(!button.Current.IsOffscreen&&IsJoinButton(button.Current.Name))joinButtons.Add(button);
        if(joinButtons.Count==1)joined=Invoke(joinButtons[0]);
       }
      }catch(Exception error){if(!Stale(error))throw;}
     }
     var unconfirmed=new Exception("Acionei a call "+channel+(String.IsNullOrEmpty(server)?"":" no servidor "+server)+", mas nao consegui confirmar a conexao de voz.");Diagnose(root,server,channel,stage,unconfirmed);return unconfirmed.Message;
    }catch(OperationCanceledException){throw;}
    catch(Exception error){Diagnose(root,server,channel,stage,error);if(Stale(error))throw new Exception("A interface do Discord mudou durante a leitura dos controles e nao consegui concluir esta tentativa. Tente novamente.");if(String.IsNullOrWhiteSpace(error.Message))throw new Exception("O Discord interrompeu o acesso aos controles na etapa: "+stage+".");throw;}
    }
   },token);
  }
 }
}
