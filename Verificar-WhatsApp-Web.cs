using System;
using System.Reflection;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Interop;
using System.Windows.Threading;
namespace CoveTests {
 public sealed class WebDocumentBox : GroupBox {
  protected override AutomationPeer OnCreateAutomationPeer(){return new WebDocumentPeer(this);}
 }
 public sealed class WebDocumentPeer : GroupBoxAutomationPeer {
  public WebDocumentPeer(WebDocumentBox box):base(box){}
  protected override AutomationControlType GetAutomationControlTypeCore(){return AutomationControlType.Document;}
 }
 public static class WhatsAppWebControls {
  public static string Run(){
   string result="No result";var window=new Window{Title="Cove WhatsApp Web fixture",Width=700,Height=500,ShowActivated=false,ShowInTaskbar=false};
   var layout=new StackPanel();window.Content=layout;
   var address=new TextBox{Text="https://web.whatsapp.com/"};AutomationProperties.SetName(address,"Address and search bar");layout.Children.Add(address);
   var doc=new WebDocumentBox{Header="WhatsApp"};AutomationProperties.SetName(doc,"WhatsApp");layout.Children.Add(doc);
   var page=new StackPanel{Margin=new Thickness(250,0,0,0)};doc.Content=page;
   var title=new TextBlock{Text="Ester"};page.Children.Add(title);
   var composer=new TextBox();AutomationProperties.SetName(composer,"Digite uma mensagem");page.Children.Add(composer);
   var timeout=new DispatcherTimer{Interval=TimeSpan.FromSeconds(20)};timeout.Tick+=(s,e)=>{result="Fixture timed out";window.Close();};
   window.Loaded+=(s,e)=>{
    var handle=new WindowInteropHelper(window).Handle;
    Task.Run(()=>{
     try{
      var type=typeof(CoveApp.Messaging);var browser=type.GetMethod("BrowserIsWhatsApp",BindingFlags.Static|BindingFlags.NonPublic);var editor=type.GetMethod("WebComposer",BindingFlags.Static|BindingFlags.NonPublic);var header=type.GetMethod("WebHeader",BindingFlags.Static|BindingFlags.NonPublic);
      var root=AutomationElement.FromHandle(handle);
      if(!(bool)browser.Invoke(null,new object[]{root})||editor.Invoke(null,new object[]{root})==null||!(bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Verified browser/document/contact not located");
      if((bool)header.Invoke(null,new object[]{root,"Other"}))throw new Exception("Wrong contact accepted");
      // Exercise the production wait loop with simulated UI delays; callbacks
      // only count attempts and never click or send to a real application.
      var waitClock=System.Diagnostics.Stopwatch.StartNew();int opens=0;
      var delayed=CoveApp.Messaging.WaitForWebContacts(()=>waitClock.ElapsedMilliseconds>=450?root:null,()=>waitClock.ElapsedMilliseconds>=50,attempt=>{opens++;return true;},()=>{},1500,100);
      if(delayed==null||opens!=1)throw new Exception("Delayed picker was clicked again while loading");
      waitClock.Restart();opens=0;long openedAt=-1;
      delayed=CoveApp.Messaging.WaitForWebContacts(()=>openedAt>=0&&waitClock.ElapsedMilliseconds-openedAt>=160?root:null,()=>openedAt>=0,attempt=>{opens++;if(opens==2)openedAt=waitClock.ElapsedMilliseconds;return true;},()=>{},1500,200);
      if(delayed==null||opens!=2)throw new Exception("Missed first open was not retried or was clicked after opening");
      opens=0;
      delayed=CoveApp.Messaging.WaitForWebContacts(()=>null,()=>false,attempt=>{opens++;return true;},()=>{},600,100);
      if(delayed!=null||opens!=3)throw new Exception("Contact wait did not stop after deadline/attempt limit");
      int checks=0;bool cancelled=false;
      try{CoveApp.Messaging.WaitForWebContacts(()=>null,()=>false,attempt=>true,()=>{if(++checks>=3)throw new OperationCanceledException();},1500,200);}catch(OperationCanceledException){cancelled=true;}
      if(!cancelled)throw new Exception("Contact wait ignored cancellation");
      waitClock.Restart();int pickerRetries=0;
      bool conversationReady=CoveApp.Messaging.WaitForWebConversation(()=>waitClock.ElapsedMilliseconds>=450,()=>{},()=>{pickerRetries++;},1800,300);
      if(!conversationReady||waitClock.ElapsedMilliseconds<750||pickerRetries==0)throw new Exception("Did not wait for delayed conversation/composer to stabilize");
      string prepared="";var sequence=new System.Collections.Generic.List<string>{"conversation-ready"};
      CoveApp.Messaging.PrepareAndSend("Oi!",()=>conversationReady,()=>prepared,()=>sequence.Add("focus"),body=>{prepared=body;sequence.Add("type");},()=>{},()=>sequence.Add("send"));
      if(String.Join(",",sequence)!="conversation-ready,focus,type,send"||prepared!="Oi!")throw new Exception("Message preparation/send did not follow conversation readiness");
      int probes=0;waitClock.Restart();
      conversationReady=CoveApp.Messaging.WaitForWebConversation(()=>{probes++;return probes<=2||probes>=5;},()=>{},()=>{},1800,300);
      if(!conversationReady||probes<7||waitClock.ElapsedMilliseconds<850)throw new Exception("Transient ready state was accepted before the conversation stabilized");
      if(CoveApp.Messaging.WaitForWebConversation(()=>false,()=>{},()=>{},300,100))throw new Exception("Unopened/wrong conversation allowed typing");
      bool searchFocused=false;int focusClicks=0,typed=0;string query="old query";
      CoveApp.Messaging.EnterContactSearch("Ester",()=>searchFocused,attempt=>{focusClicks++;searchFocused=true;},name=>{typed++;query=typed==1?"":name;},()=>query,()=>{},60);
      if(query!="Ester"||typed!=2||focusClicks!=2)throw new Exception("Search did not click/type/retry a missed keyboard input");
      typed=0;bool failedSearch=false;
      try{CoveApp.Messaging.EnterContactSearch("Ester",()=>true,attempt=>{},name=>{typed++;},()=>"wrong query",()=>{},1);}catch(Exception){failedSearch=true;}
      if(!failedSearch||typed!=3)throw new Exception("Unverified query allowed contact selection or search retries were unbounded");
      typed=0;cancelled=false;
      try{CoveApp.Messaging.EnterContactSearch("Ester",()=>true,attempt=>{},name=>{typed++;},()=>"",()=>{throw new OperationCanceledException();},1);}catch(OperationCanceledException){cancelled=true;}
      if(!cancelled||typed!=0)throw new Exception("Cancelled search still typed");
      GroupBox picker=null;StackPanel contacts=null;
      window.Dispatcher.Invoke(new Action(()=>{
       picker=new GroupBox{Header="Nova conversa"};AutomationProperties.SetName(picker,"Nova conversa");contacts=new StackPanel();picker.Content=contacts;
       var search=new TextBox{Text="Ester"};AutomationProperties.SetName(search,"Pesquisar nome ou numero");contacts.Children.Add(search);
       var row=new GroupBox{Header="Foto de perfil",Content=new TextBlock{Text="Ester"}};AutomationProperties.SetName(row,"Foto de perfil");contacts.Children.Add(row);page.Children.Add(picker);window.UpdateLayout();
      }));
      var findPanel=type.GetMethod("WebContactPanel",BindingFlags.Static|BindingFlags.NonPublic);var findContacts=type.GetMethod("WebContacts",BindingFlags.Static|BindingFlags.NonPublic);
      var panel=(AutomationElement)findPanel.Invoke(null,new object[]{root});
      if(panel==null)throw new Exception("Contact picker not located");
      var findSearch=type.GetMethod("WebContactSearch",BindingFlags.Static|BindingFlags.NonPublic);
      TextBox unnamedSearch=null,extraSearch=null;
      window.Dispatcher.Invoke(new Action(()=>{
       unnamedSearch=(TextBox)contacts.Children[0];AutomationProperties.SetName(unnamedSearch,"");AutomationProperties.SetHelpText(unnamedSearch,"Pesquisar nome ou numero");window.UpdateLayout();
      }));
      if(findSearch.Invoke(null,new object[]{panel})==null)throw new Exception("Search placeholder/help text not recognized");
      window.Dispatcher.Invoke(new Action(()=>{AutomationProperties.SetHelpText(unnamedSearch,"");window.UpdateLayout();}));
      if(findSearch.Invoke(null,new object[]{panel})==null)throw new Exception("Unique unnamed search input not recognized");
      window.Dispatcher.Invoke(new Action(()=>{extraSearch=new TextBox();contacts.Children.Add(extraSearch);window.UpdateLayout();}));
      if(findSearch.Invoke(null,new object[]{panel})!=null)throw new Exception("Ambiguous unnamed fields accepted as contact search");
      window.Dispatcher.Invoke(new Action(()=>{contacts.Children.Remove(extraSearch);AutomationProperties.SetName(unnamedSearch,"Pesquisar nome ou numero");window.UpdateLayout();}));
      window.Dispatcher.Invoke(new Action(()=>{picker.Header=null;AutomationProperties.SetName(picker,"");contacts.Children.Insert(0,new TextBlock{Text="Nova conversa"});window.UpdateLayout();}));
      panel=(AutomationElement)findPanel.Invoke(null,new object[]{root});
      if(panel==null||findSearch.Invoke(null,new object[]{panel})==null)throw new Exception("Heading-only picker with unnamed container not located");
      var searchElement=(AutomationElement)findSearch.Invoke(null,new object[]{panel});long fixtureWindow=handle.ToInt64();
      if(!CoveApp.Messaging.CanClickElementAt(searchElement,searchElement,fixtureWindow,fixtureWindow))throw new Exception("Exact input hit rejected");
      if(!CoveApp.Messaging.CanClickElementAt(searchElement,panel,fixtureWindow,fixtureWindow))throw new Exception("Chromium enclosing-container hit falsely reported as another window");
      var unrelated=(AutomationElement)editor.Invoke(null,new object[]{root});
      if(CoveApp.Messaging.CanClickElementAt(searchElement,unrelated,fixtureWindow,fixtureWindow))throw new Exception("Unrelated control overlay accepted");
      if(CoveApp.Messaging.CanClickElementAt(searchElement,searchElement,fixtureWindow+1,fixtureWindow))throw new Exception("Different native window accepted as input hit");
      if(CoveApp.Messaging.CanClickElementAt(searchElement,root,fixtureWindow,fixtureWindow))throw new Exception("Whole-window hit accepted as a field");
      if(CoveApp.Messaging.CanClickElementAt(searchElement,searchElement,0,fixtureWindow))throw new Exception("Unknown native window accepted");
      var matches=(System.Collections.Generic.List<AutomationElement>)findContacts.Invoke(null,new object[]{panel,"Ester"});
      if(matches.Count!=1)throw new Exception("Nested Group contact row not uniquely located: "+matches.Count);
      if(matches[0].Current.ControlType!=ControlType.Text||matches[0].Current.Name!="Ester")throw new Exception("Click target is a wrapper instead of the exact contact name");
      window.Dispatcher.Invoke(new Action(()=>{
       var wrong=new StackPanel();wrong.Children.Add(new TextBlock{Text="Other person"});wrong.Children.Add(new TextBlock{Text="Ester"});
       contacts.Children.Insert(1,new GroupBox{Content=wrong});window.UpdateLayout();
      }));
      matches=(System.Collections.Generic.List<AutomationElement>)findContacts.Invoke(null,new object[]{panel,"Ester"});
      if(matches.Count!=1||matches[0].Current.Name!="Ester")throw new Exception("Status in the first result confused with contact identity");
      window.Dispatcher.Invoke(new Action(()=>{contacts.Children.RemoveAt(1);window.UpdateLayout();}));
      Button namedContact=null;
      window.Dispatcher.Invoke(new Action(()=>{namedContact=new Button{Content="Button Contact"};AutomationProperties.SetName(namedContact,"Button Contact");contacts.Children.Add(namedContact);window.UpdateLayout();}));
      var buttonMatches=(System.Collections.Generic.List<AutomationElement>)findContacts.Invoke(null,new object[]{panel,"Button Contact"});
      if(buttonMatches.Count!=1)throw new Exception("Contact exposed as a named button was not located uniquely");
      window.Dispatcher.Invoke(new Action(()=>{contacts.Children.Remove(namedContact);window.UpdateLayout();}));
      if((bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Open picker mistaken for ready conversation");
      window.Dispatcher.Invoke(new Action(()=>{contacts.Children.Add(new GroupBox{Header="Outra foto",Content=new TextBlock{Text="Ester"}});window.UpdateLayout();}));
      matches=(System.Collections.Generic.List<AutomationElement>)findContacts.Invoke(null,new object[]{panel,"Ester"});
      if(matches.Count!=2)throw new Exception("Duplicate contacts not detected");
      matches=(System.Collections.Generic.List<AutomationElement>)findContacts.Invoke(null,new object[]{panel,"Other"});
      if(matches.Count!=0)throw new Exception("Unrelated contact selected");
      window.Dispatcher.Invoke(new Action(()=>{page.Children.Remove(picker);window.UpdateLayout();}));
      if(!(bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Ready conversation not recognized after picker closed");
      window.Dispatcher.Invoke(new Action(()=>{address.Text="https://web.whatsapp.com.example.com/";}));
      if((bool)browser.Invoke(null,new object[]{root})||editor.Invoke(null,new object[]{root})!=null)throw new Exception("Wrong website accepted");
      window.Dispatcher.Invoke(new Action(()=>{var spoof=new TextBox{Text="https://web.whatsapp.com/"};AutomationProperties.SetName(spoof,"Address and search bar");page.Children.Add(spoof);}));
      if((bool)browser.Invoke(null,new object[]{root}))throw new Exception("Webpage spoofed native address bar");
      foreach(string bad in new[]{"http://web.whatsapp.com/","https://web.whatsapp.com:123/","https://evil@web.whatsapp.com/","https://whatsapp.com/","javascript:alert(1)"})if(CoveApp.Messaging.IsWhatsAppWebAddress(bad))throw new Exception("Unsafe URL: "+bad);
      if(!CoveApp.Messaging.IsWhatsAppWebAddress("web.whatsapp.com"))throw new Exception("Chrome address without scheme rejected");
      result="OK: delayed conversation/composer must stabilize before focus/type/send; transient/wrong conversation blocked; safe Chrome clicks and search retained. Own UI/simulated input only; no real messages.";
     }catch(Exception error){result=error.ToString();}
     finally{window.Dispatcher.BeginInvoke(new Action(()=>window.Close()));}
    });
   };
   timeout.Start();window.ShowDialog();timeout.Stop();return result;
  }
 }
}
