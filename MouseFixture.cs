using System;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Diagnostics;
public static class CoveMouseFixture {
 [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
 [STAThread] public static void Main(string[] args){
  try{SetProcessDpiAwarenessContext(new IntPtr(-4));}catch(EntryPointNotFoundException){}
  Application.EnableVisualStyles();
  string report=args[0];int selected=0,voice=0,wrong=0;
  var form=new Form{Text=args[1],StartPosition=FormStartPosition.Manual,Location=new Point(Int32.Parse(args[2]),Int32.Parse(args[3])),ClientSize=new Size(310,250),TopMost=true,AutoScaleMode=AutoScaleMode.None};
  var servers=new GroupBox{Text="Servers",AccessibleName="Servers",Bounds=new Rectangle(10,10,290,80)};form.Controls.Add(servers);
  var caps=new Button{Text="CAPS",AccessibleName="CAPS",Bounds=new Rectangle(12,24,120,34)};servers.Controls.Add(caps);
  var other=new Button{Text="OUTRO",AccessibleName="OUTRO",Bounds=new Rectangle(150,24,120,34)};servers.Controls.Add(other);
  var channels=new GroupBox{Text="Channels",AccessibleName="Channels",Bounds=new Rectangle(10,100,290,90)};form.Controls.Add(channels);
  var text=new Button{Text="Texto geral",AccessibleName="geral (canal de texto)",Bounds=new Rectangle(12,28,120,34)};channels.Controls.Add(text);
  var call=new Button{Text="Voz geral",AccessibleName="geral (canal de voz)",Bounds=new Rectangle(150,28,120,34)};channels.Controls.Add(call);
  var status=new Label{Text="Teste do mouse. Esc interrompe.",Bounds=new Rectangle(12,205,288,35)};form.Controls.Add(status);
  Action write=()=>File.WriteAllText(report,"server="+selected+"\nvoice="+voice+"\nwrong="+wrong);
  caps.Click+=(s,e)=>{selected++;form.Text="geral | CAPS - Discord";status.Text="Servidor selecionado";write();};
  other.Click+=(s,e)=>{wrong++;write();};text.Click+=(s,e)=>{wrong++;write();};
  call.Click+=(s,e)=>{if(selected!=1)wrong++;voice++;status.Text="Clique de voz confirmado";write();};
  var lifetime=Stopwatch.StartNew();var guard=new Timer{Interval=500};
  guard.Tick+=(s,e)=>{bool parentAlive=true;if(args.Length>4){try{using(var parent=Process.GetProcessById(Int32.Parse(args[4])))parentAlive=!parent.HasExited;}catch(ArgumentException){parentAlive=false;}}if(!parentAlive||lifetime.Elapsed.TotalSeconds>15)form.Close();};
  form.Shown+=(s,e)=>{write();guard.Start();};form.FormClosed+=(s,e)=>{guard.Stop();guard.Dispose();};Application.Run(form);
 }
}
