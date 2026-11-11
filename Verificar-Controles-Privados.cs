using System;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Threading;
namespace CoveTests {
 public static class PrivateControls {
  public static string Run(){
   string result="No result";var window=new Window{Title="Cove private controls fixture",Width=360,Height=300,ShowActivated=false,ShowInTaskbar=false};
   var panel=new StackPanel();window.Content=panel;
   var toolbar=new ToolBar();var title=new TextBlock{Text="Ester"};toolbar.Items.Add(title);panel.Children.Add(toolbar);
   var composer=new TextBox();AutomationProperties.SetName(composer,"Message @Other");panel.Children.Add(composer);
   var group=new GroupBox{Header="Quick Switcher",Visibility=Visibility.Collapsed};AutomationProperties.SetName(group,"Quick Switcher");panel.Children.Add(group);
   var combo=new ComboBox{IsEditable=true};AutomationProperties.SetName(combo,"Where would you like to go?");group.Content=combo;
   var delay=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(350)};delay.Tick+=(s,e)=>{delay.Stop();group.Visibility=Visibility.Visible;};
   var timeout=new DispatcherTimer{Interval=TimeSpan.FromSeconds(15)};timeout.Tick+=(s,e)=>{result="Fixture timed out";window.Close();};
   window.Loaded+=(s,e)=>{
    var handle=new WindowInteropHelper(window).Handle;
    Task.Run(()=>{
     try{
      var type=typeof(CoveApp.DiscordCall);var picker=type.GetMethod("PickerField",BindingFlags.Static|BindingFlags.NonPublic);var fill=type.GetMethod("FillPicker",BindingFlags.Static|BindingFlags.NonPublic);var header=type.GetMethod("PrivateHeader",BindingFlags.Static|BindingFlags.NonPublic);
      var root=AutomationElement.FromHandle(handle);var args=new object[]{root,null};
      if(picker.Invoke(null,args)!=null)throw new Exception("Hidden picker accepted");
      window.Dispatcher.Invoke(new Action(()=>delay.Start()));
      AutomationElement field=null;var until=DateTime.UtcNow.AddSeconds(5);
      while(field==null&&DateTime.UtcNow<until){Thread.Sleep(100);args=new object[]{AutomationElement.FromHandle(handle),null};field=picker.Invoke(null,args) as AutomationElement;}
      if(field==null||args[1]==null)throw new Exception("Delayed editable combobox picker not found");
      object value;if(!field.TryGetCurrentPattern(ValuePattern.Pattern,out value))throw new Exception("Fixture requires ValuePattern; keyboard must not be exercised");
      fill.Invoke(null,new object[]{field,"Ester"});
      if(((ValuePattern)value).Current.Value!="Ester")throw new Exception("Picker not filled");
      if((bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Wrong recipient composer accepted");
      window.Dispatcher.Invoke(new Action(()=>{group.Visibility=Visibility.Collapsed;AutomationProperties.SetName(composer,"Message @Ester");}));
      if(!(bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Private message wrongly requires a voice-call button");
      if(CoveApp.Messaging.ComposerRecipientMatches("Message #Ester","Ester"))throw new Exception("Guild composer accepted as private");
      foreach(string label in new[]{"Conversar com @Ester","Mensagem para Ester","Enviar mensagem a @Ester","Message Ester"}){
       window.Dispatcher.Invoke(new Action(()=>AutomationProperties.SetName(composer,label)));
       if(!(bool)header.Invoke(null,new object[]{root,"Ester"})||CoveApp.Messaging.FindDiscordComposer(root,"Ester",false)==null)throw new Exception("Localized composer not recognized: "+label);
      }
      window.Dispatcher.Invoke(new Action(()=>AutomationProperties.SetName(composer,"Conversar em #Ester")));
      if((bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Guild channel mistaken for private input");
      window.Dispatcher.Invoke(new Action(()=>AutomationProperties.SetName(composer,"Digite uma mensagem")));
      if((bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Generic input accepted without private header evidence");
      window.Dispatcher.Invoke(new Action(()=>{var voice=new Button{Content="Start Voice Call"};toolbar.Items.Add(voice);}));
      if(!(bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Generic input with verified private header rejected");
      window.Dispatcher.Invoke(new Action(()=>AutomationProperties.SetHelpText(composer,"Search messages")));
      if((bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Message search mistaken for composer");
      window.Dispatcher.Invoke(new Action(()=>{AutomationProperties.SetHelpText(composer,"");composer.Text="DRAFT-CANARY-DO-NOT-LOG";}));
      if(CoveApp.Messaging.DescribeDiscordInputs(root).Contains("DRAFT-CANARY"))throw new Exception("Diagnostic logged draft text");
      TextBox duplicate=null;
      window.Dispatcher.Invoke(new Action(()=>{duplicate=new TextBox();AutomationProperties.SetName(duplicate,"Message @Ester");panel.Children.Add(duplicate);}));
      if((bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Multiple composers accepted");
      window.Dispatcher.Invoke(new Action(()=>{panel.Children.Remove(duplicate);panel.Children.Remove(toolbar);var region=new GroupBox{Header="Channel header"};AutomationProperties.SetName(region,"Channel header");region.Content=new TextBlock{Text="Ester"};panel.Children.Insert(0,region);AutomationProperties.SetName(composer,"Conversar com @Ester");}));
      if(!(bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Region header rejected");
      RichTextBox rich=null;
      window.Dispatcher.Invoke(new Action(()=>{composer.Visibility=Visibility.Collapsed;rich=new RichTextBox();AutomationProperties.SetName(rich,"Conversar com @Ester");panel.Children.Add(rich);}));
      if(!(bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Document/TextPattern composer rejected");
      var wait=type.GetMethod("WaitForPrivateMessage",BindingFlags.Static|BindingFlags.NonPublic);int reads=0;
      Func<AutomationElement> changing=()=>{
       reads++;if(reads<=2)throw new ElementNotAvailableException();
       if(reads==4)window.Dispatcher.Invoke(new Action(()=>{panel.Children.Remove(rich);rich=new RichTextBox();AutomationProperties.SetName(rich,"Conversar com @Ester");panel.Children.Add(rich);}));
       return AutomationElement.FromHandle(handle);
      };
      var watch=System.Diagnostics.Stopwatch.StartNew();
      if(wait.Invoke(null,new object[]{changing,"Ester",CancellationToken.None})==null||reads<6||watch.ElapsedMilliseconds<800)throw new Exception("Changing input was not reacquired and stabilized");
      if(CoveApp.DiscordCall.PrivateFailureMessage("enviar mensagem privada").Contains("Nada foi enviado"))throw new Exception("Uncertain send reported as not sent");
      StackPanel messages=null;
      window.Dispatcher.Invoke(new Action(()=>{window.Height=650;messages=new StackPanel();AutomationProperties.SetName(messages,"Messages");panel.Children.Add(messages);var old=new TextBlock{Text="Recado de teste"};AutomationProperties.SetAutomationId(old,"message-content-1-1");messages.Children.Add(old);}));
      var prior=CoveApp.Messaging.MessageEvidence(root,AutomationElement.FromHandle(handle).FindFirst(TreeScope.Descendants,new PropertyCondition(AutomationElement.NameProperty,"Conversar com @Ester")),"Recado de teste");
      if(prior.Count!=1||CoveApp.Messaging.NewMessageAppeared(prior,CoveApp.Messaging.MessageEvidence(root,CoveApp.Messaging.FindDiscordComposer(root,"Ester",false),"Recado de teste")))throw new Exception("Old message treated as newly sent");
      window.Dispatcher.Invoke(new Action(()=>{var sent=new RichTextBox{IsReadOnly=true};AutomationProperties.SetName(sent,"Message content");AutomationProperties.SetAutomationId(sent,"message-content-1-2");sent.Document.Blocks.Add(new System.Windows.Documents.Paragraph(new System.Windows.Documents.Run("Recado de teste")));messages.Children.Add(sent);}));
      var after=CoveApp.Messaging.MessageEvidence(root,CoveApp.Messaging.FindDiscordComposer(root,"Ester",false),"Recado de teste");
      var bubbleUntil=DateTime.UtcNow.AddSeconds(3);while(!CoveApp.Messaging.NewMessageAppeared(prior,after)&&DateTime.UtcNow<bubbleUntil){Thread.Sleep(100);after=CoveApp.Messaging.MessageEvidence(root,CoveApp.Messaging.FindDiscordComposer(root,"Ester",false),"Recado de teste");}
      if(!CoveApp.Messaging.NewMessageAppeared(prior,after))throw new Exception("New document bubble not recognized as send evidence");
      result="OK: localized/document inputs, stale controls and delayed updates; new message bubble recognized, old identical message excluded; no draft logged, no send retry. Own UI only, no Discord action.";
     }catch(Exception error){result=error.ToString();}
     finally{window.Dispatcher.BeginInvoke(new Action(()=>window.Close()));}
    });
   };
   timeout.Start();window.ShowDialog();timeout.Stop();delay.Stop();return result;
  }
 }
}
