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
 public static class DiscordNavigation {
  static void After(int milliseconds,Action update){var timer=new DispatcherTimer{Interval=TimeSpan.FromMilliseconds(milliseconds)};timer.Tick+=(s,e)=>{timer.Stop();update();};timer.Start();}
  public static string Run(){return Run(false,false);}
  public static string Run(bool alreadyOpen,bool inFolder){return Run(alreadyOpen,inFolder,false);}
  public static string Run(bool alreadyOpen,bool inFolder,bool recreateViews){return Run(alreadyOpen,inFolder,recreateViews,false);}
  public static string Run(bool alreadyOpen,bool inFolder,bool recreateViews,bool delayedChanges){return Run(alreadyOpen,inFolder,recreateViews,delayedChanges,false);}
  public static string Run(bool alreadyOpen,bool inFolder,bool recreateViews,bool delayedChanges,bool linkedMode){
   string result="No result";int serverClicks=0,voiceClicks=0,textClicks=0,otherClicks=0,folderClicks=0,categoryExpands=0;
   var window=new Window{Title="outro | OUTRO - Discord",Width=310,Height=360,ShowActivated=false,ShowInTaskbar=false,ResizeMode=ResizeMode.NoResize};
   window.Left=Math.Max(0,SystemParameters.WorkArea.Right-330);window.Top=Math.Max(0,SystemParameters.WorkArea.Bottom-390);
   var layout=new StackPanel{Margin=new Thickness(12)};window.Content=layout;
   var servers=new GroupBox{Header="Servers"};AutomationProperties.SetName(servers,"Servers");layout.Children.Add(servers);
   if(linkedMode)servers.Visibility=Visibility.Collapsed;
   var serverItems=new StackPanel();servers.Content=serverItems;
   var caps=new Button{Content="CAPS",Margin=new Thickness(2)};serverItems.Children.Add(caps);
   if(alreadyOpen||inFolder)caps.Visibility=Visibility.Collapsed;
   Button folder=null;
   if(inFolder){folder=new Button{Content="OUTRO, CAPS, pasta , 3 menções não lidas",Margin=new Thickness(2)};serverItems.Children.Add(folder);}
   var other=new Button{Content="OUTRO",Margin=new Thickness(2)};serverItems.Children.Add(other);
   var channels=new GroupBox{Header="Channels"};AutomationProperties.SetName(channels,"Channels");layout.Children.Add(channels);
   if(alreadyOpen){AutomationProperties.SetName(channels,"CAPS (servidor)");window.Title="Discord";}
   var channelItems=new StackPanel();channels.Content=channelItems;
   var text=new Button{Content="🗨️-geral (canal de texto)",Margin=new Thickness(2)};AutomationProperties.SetHelpText(text,"Canal de texto");channelItems.Children.Add(text);
   var voice=new Button{Content="🔉-geral (canal de voz), não lida",Margin=new Thickness(2)};AutomationProperties.SetHelpText(voice,"Canal de voz");channelItems.Children.Add(voice);
   var connection=new GroupBox{Header="Conexao",Height=60};layout.Children.Add(connection);
   var connectionItems=new StackPanel();connection.Content=connectionItems;
   Func<GroupBox> newChannels=()=>{
    var group=new GroupBox{Header="Channels"};AutomationProperties.SetName(group,"Channels");var panel=new StackPanel();group.Content=panel;
    var textButton=new Button{Content="🗨️-geral (canal de texto)"};var voiceButton=new Button{Content="🔉-geral (canal de voz), não lida"};panel.Children.Add(textButton);panel.Children.Add(voiceButton);
    textButton.Click+=(s,e)=>{textClicks++;};voiceButton.Click+=(s,e)=>{voiceClicks++;connectionItems.Children.Add(new TextBlock{Text="geral / CAPS"});connectionItems.Children.Add(new Button{Content="Desconectar"});};
    return group;
   };
   if(folder!=null)folder.Click+=(s,e)=>{
    folderClicks++;
    if(!recreateViews){caps.Visibility=Visibility.Visible;return;}
    // Remove the providers from the tree, matching Chromium's re-render.
    var freshServers=new GroupBox{Header="Servers"};AutomationProperties.SetName(freshServers,"Servers");var freshItems=new StackPanel();freshServers.Content=freshItems;var freshCaps=new Button{Content="CAPS"};if(delayedChanges)After(400,()=>freshItems.Children.Add(freshCaps));else freshItems.Children.Add(freshCaps);layout.Children.RemoveAt(0);layout.Children.Insert(0,freshServers);
    freshCaps.Click+=(sender,args)=>{
     serverClicks++;window.Title="geral | CAPS - Discord";
     var categoryGroup=new GroupBox{Header="Channels"};AutomationProperties.SetName(categoryGroup,"Channels");var tree=new TreeView();categoryGroup.Content=tree;var category=new TreeViewItem{Header="Geral (categoria)"};category.Items.Add(new TextBlock{Text="Collapsed contents"});tree.Items.Add(category);layout.Children.RemoveAt(1);layout.Children.Insert(1,categoryGroup);
     category.Expanded+=(owner,eventArgs)=>{categoryExpands++;eventArgs.Handled=true;var replacement=newChannels();if(delayedChanges){var deferred=replacement.Content;replacement.Content=null;After(400,()=>replacement.Content=deferred);}layout.Children.RemoveAt(1);layout.Children.Insert(1,replacement);};
    };
   };
   caps.Click+=(s,e)=>{serverClicks++;window.Title="geral | CAPS - Discord";};
   other.Click+=(s,e)=>{otherClicks++;};text.Click+=(s,e)=>{textClicks++;};
   voice.Click+=(s,e)=>{voiceClicks++;connectionItems.Children.Add(new TextBlock{Text="geral / CAPS"});connectionItems.Children.Add(new Button{Content="Desconectar"});};
   var cancel=new CancellationTokenSource();var timeout=new DispatcherTimer{Interval=TimeSpan.FromSeconds(20)};
   timeout.Tick+=(s,e)=>{result="Timeout";cancel.Cancel();window.Close();};
   window.ContentRendered+=(s,e)=>{
    var handle=new WindowInteropHelper(window).Handle;timeout.Start();
    Task.Run(()=>{
     try{
      var root=AutomationElement.FromHandle(handle);var type=typeof(CoveApp.DiscordCall);
      var flags=BindingFlags.NonPublic|BindingFlags.Static;
      if(!linkedMode){bool selected=(bool)type.GetMethod("SelectServer",flags).Invoke(null,new object[]{root,"CAPS",cancel.Token});if(!selected)throw new Exception("Server was not selected");}
      type.GetMethod(linkedMode?"SelectLinkedVoiceChannel":"SelectVoiceChannel",flags).Invoke(null,new object[]{root,"CAPS","geral",cancel.Token});
      Thread.Sleep(300);
      bool connected=(bool)type.GetMethod("Connected",flags).Invoke(null,new object[]{root,"CAPS","geral"});
      if(serverClicks!=(alreadyOpen?0:1)||folderClicks!=(inFolder?1:0)||categoryExpands!=(recreateViews?1:0)||voiceClicks!=1||textClicks!=0||otherClicks!=0||!connected)throw new Exception("Incorrect control or connection: "+serverClicks+","+voiceClicks+","+textClicks+","+otherClicks+","+connected+", folders="+folderClicks+", categories="+categoryExpands);
      result="OK: UI Automation CAPS/voice geral; alreadyOpen="+alreadyOpen+", folder="+inFolder+", recreatedViews="+recreateViews+", delayedChanges="+delayedChanges+", linkedMode="+linkedMode+"; text and other server untouched; connection verified in fixture.";
     }catch(Exception error){result="FAIL: "+error.GetBaseException().Message;}
     finally{window.Dispatcher.BeginInvoke(new Action(()=>{timeout.Stop();window.Close();}));}
    });
   };
   try{window.ShowDialog();}finally{timeout.Stop();cancel.Cancel();cancel.Dispose();}
   return result;
  }
 }
}
