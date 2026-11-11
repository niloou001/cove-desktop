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
   var timeout=new DispatcherTimer{Interval=TimeSpan.FromSeconds(12)};timeout.Tick+=(s,e)=>{result="Fixture timed out";window.Close();};
   window.Loaded+=(s,e)=>{
    var handle=new WindowInteropHelper(window).Handle;
    Task.Run(()=>{
     try{
      var type=typeof(CoveApp.Messaging);var browser=type.GetMethod("BrowserIsWhatsApp",BindingFlags.Static|BindingFlags.NonPublic);var editor=type.GetMethod("WebComposer",BindingFlags.Static|BindingFlags.NonPublic);var header=type.GetMethod("WebHeader",BindingFlags.Static|BindingFlags.NonPublic);
      var root=AutomationElement.FromHandle(handle);
      if(!(bool)browser.Invoke(null,new object[]{root})||editor.Invoke(null,new object[]{root})==null||!(bool)header.Invoke(null,new object[]{root,"Ester"}))throw new Exception("Verified browser/document/contact not located");
      if((bool)header.Invoke(null,new object[]{root,"Other"}))throw new Exception("Wrong contact accepted");
      window.Dispatcher.Invoke(new Action(()=>{address.Text="https://web.whatsapp.com.example.com/";}));
      if((bool)browser.Invoke(null,new object[]{root})||editor.Invoke(null,new object[]{root})!=null)throw new Exception("Wrong website accepted");
      window.Dispatcher.Invoke(new Action(()=>{var spoof=new TextBox{Text="https://web.whatsapp.com/"};AutomationProperties.SetName(spoof,"Address and search bar");page.Children.Add(spoof);}));
      if((bool)browser.Invoke(null,new object[]{root}))throw new Exception("Webpage spoofed native address bar");
      foreach(string bad in new[]{"http://web.whatsapp.com/","https://web.whatsapp.com:123/","https://evil@web.whatsapp.com/","https://whatsapp.com/","javascript:alert(1)"})if(CoveApp.Messaging.IsWhatsAppWebAddress(bad))throw new Exception("Unsafe URL: "+bad);
      if(!CoveApp.Messaging.IsWhatsAppWebAddress("web.whatsapp.com"))throw new Exception("Chrome address without scheme rejected");
      result="OK: native browser URL, scoped web document, exact contact/composer, wrong recipient/domain and page-spoofed address blocked. Own fixture only; no browser/message action.";
     }catch(Exception error){result=error.ToString();}
     finally{window.Dispatcher.BeginInvoke(new Action(()=>window.Close()));}
    });
   };
   timeout.Start();window.ShowDialog();timeout.Stop();return result;
  }
 }
}
