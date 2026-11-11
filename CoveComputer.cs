using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
namespace CoveApp {
 public static class Computer {
  [StructLayout(LayoutKind.Sequential)] struct KEYBOARD {public ushort key,scan;public uint flags,time;public IntPtr extra;}
  [StructLayout(LayoutKind.Sequential)] struct MOUSE {public int x,y;public uint data,flags,time;public IntPtr extra;}
  [StructLayout(LayoutKind.Explicit)] struct UNION {[FieldOffset(0)]public KEYBOARD keyboard;[FieldOffset(0)]public MOUSE mouse;}
  [StructLayout(LayoutKind.Sequential)] struct INPUT {public uint type;public UNION value;}
  delegate bool WindowCallback(IntPtr window,IntPtr param);
  [DllImport("user32.dll")] static extern bool EnumWindows(WindowCallback callback,IntPtr param);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window,StringBuilder title,int count);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool IsWindow(IntPtr window);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window,int command);
  [DllImport("user32.dll",SetLastError=true)] static extern bool SetCursorPos(int x,int y);
  [DllImport("user32.dll",SetLastError=true)] static extern bool SetPhysicalCursorPos(int x,int y);
  [DllImport("user32.dll",SetLastError=true)] static extern bool GetPhysicalCursorPos(out DesktopPoint point);
  [DllImport("user32.dll",SetLastError=true)] static extern bool GetCursorPos(out DesktopPoint point);
  [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr window);
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
  [StructLayout(LayoutKind.Sequential)] public struct DesktopPoint {public int X,Y;public DesktopPoint(int x,int y){X=x;Y=y;}}
  [StructLayout(LayoutKind.Sequential)] public struct DisplayBounds {public int Left,Top,Right,Bottom;public DisplayBounds(int left,int top,int right,int bottom){Left=left;Top=top;Right=right;Bottom=bottom;}}
  delegate bool MonitorCallback(IntPtr monitor,IntPtr dc,ref DisplayBounds bounds,IntPtr parameter);
  [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr dc,IntPtr clip,MonitorCallback callback,IntPtr parameter);
  public sealed class PhysicalCoordinates : IDisposable {
   IntPtr previous;
   public PhysicalCoordinates(){try{previous=SetThreadDpiAwarenessContext(new IntPtr(-4));}catch(EntryPointNotFoundException){}}
   public void Dispose(){if(previous!=IntPtr.Zero){SetThreadDpiAwarenessContext(previous);previous=IntPtr.Zero;}}
  }
  public static DisplayBounds[] Displays(){
   using(new PhysicalCoordinates()){
    var displays=new List<DisplayBounds>();
    MonitorCallback callback=(IntPtr monitor,IntPtr dc,ref DisplayBounds rect,IntPtr parameter)=>{displays.Add(rect);return true;};
    if(!EnumDisplayMonitors(IntPtr.Zero,IntPtr.Zero,callback,IntPtr.Zero))throw new Exception("Nao consegui identificar os monitores.");
    return displays.ToArray();
   }
  }
  public static bool OnDisplay(int x,int y,DisplayBounds[] displays){foreach(var d in displays)if(x>=d.Left&&x<d.Right&&y>=d.Top&&y<d.Bottom)return true;return false;}
  public static DesktopPoint Position(){using(new PhysicalCoordinates()){DesktopPoint point;if(GetPhysicalCursorPos(out point)||GetCursorPos(out point))return point;throw new Exception("Nao consegui ler o mouse nesta sessao do Windows (codigo "+Marshal.GetLastWin32Error()+").");}}
  static bool SetPhysical(int x,int y){using(new PhysicalCoordinates()){return SetPhysicalCursorPos(x,y)||SetCursorPos(x,y);}}
  public static DesktopPoint[] Movement(DesktopPoint start,DesktopPoint end,int steps){
   if(steps<1||steps>200)throw new ArgumentOutOfRangeException("steps");var path=new DesktopPoint[steps];
   for(int i=1;i<=steps;i++){double t=i/(double)steps;double eased=t*t*(3-2*t);path[i-1]=new DesktopPoint((int)Math.Round(start.X+((double)end.X-start.X)*eased),(int)Math.Round(start.Y+((double)end.Y-start.Y)*eased));}return path;
  }
  static bool Near(DesktopPoint a,DesktopPoint b,int tolerance){return Math.Abs((long)a.X-b.X)<=tolerance&&Math.Abs((long)a.Y-b.Y)<=tolerance;}
  public static void CheckMouseCancel(CancellationToken token){token.ThrowIfCancellationRequested();if((GetAsyncKeyState(27)&0x8000)!=0)throw new OperationCanceledException("Movimento interrompido pela tecla Esc.");}
  public static void RequireTargetForeground(){if(Target==0||GetForegroundWindow()!=new IntPtr(Target))throw new OperationCanceledException("A janela ativa mudou. Parei o mouse.");}
  public static void PrepareTargetMouse(){Activate();}
  public static void MoveSmooth(int x,int y,CancellationToken token){
   if(!OnDisplay(x,y,Displays()))throw new Exception("O alvo nao esta em um monitor conectado.");
   var last=Position();var path=Movement(last,new DesktopPoint(x,y),16);
   foreach(var point in path){
    CheckMouseCancel(token);RequireTargetForeground();if(!Near(Position(),last,4))throw new OperationCanceledException("Voce moveu o mouse. Acao interrompida.");
    if(!SetPhysical(point.X,point.Y))throw new Exception("O Windows nao permitiu mover o ponteiro.");
    last=Position();Thread.Sleep(12);
   }
   if(!Near(Position(),new DesktopPoint(x,y),2))throw new Exception("O ponteiro nao chegou ao alvo. Nao cliquei.");
  }
  public static void ClickFocusedTarget(int x,int y,CancellationToken token){
   CheckMouseCancel(token);RequireTargetForeground();if(!Near(Position(),new DesktopPoint(x,y),2))throw new OperationCanceledException("O mouse saiu do alvo. Nao cliquei.");
   Send(new[]{new INPUT{type=0,value=new UNION{mouse=new MOUSE{flags=2}}},new INPUT{type=0,value=new UNION{mouse=new MOUSE{flags=4}}}});
  }
  [DllImport("user32.dll")] static extern int GetSystemMetrics(int index);
  [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count,INPUT[] inputs,int size);
  public static long Target;
  public static long ForegroundHandle(){return GetForegroundWindow().ToInt64();}
  public static void FocusHandle(long handle){
   IntPtr window=new IntPtr(handle);uint pid;
   if(handle==0||!IsWindow(window))throw new Exception("A janela de destino foi fechada.");
   GetWindowThreadProcessId(window,out pid);
   if(pid==(uint)System.Diagnostics.Process.GetCurrentProcess().Id)throw new Exception("Escolha uma janela de outro aplicativo.");
   if(IsIconic(window))ShowWindow(window,9);
   if(GetForegroundWindow()!=window&&!SetForegroundWindow(window))throw new Exception("O Windows impediu a ativacao do Discord.");
   Target=handle;
  }
  static string Title(IntPtr window){var s=new StringBuilder(1024);GetWindowText(window,s,s.Capacity);return s.ToString();}
  public static string[] Windows(){var list=new List<string>();EnumWindows((w,p)=>{string title=Title(w);if(IsWindowVisible(w)&&title.Length>0)list.Add(title);return true;},IntPtr.Zero);return list.ToArray();}
  public static string Focus(string title){
   var matches=new List<IntPtr>();var exact=new List<IntPtr>();
   EnumWindows((w,p)=>{string t=Title(w);if(IsWindowVisible(w)&&t.IndexOf(title,StringComparison.OrdinalIgnoreCase)>=0){matches.Add(w);if(t.Equals(title,StringComparison.OrdinalIgnoreCase))exact.Add(w);}return true;},IntPtr.Zero);
   if(exact.Count==1)matches=exact;
   if(matches.Count!=1)throw new Exception(matches.Count==0?"Nao encontrei essa janela. Diga listar janelas.":"Mais de uma janela corresponde. Informe o titulo completo.");
   IntPtr window=matches[0];uint pid;GetWindowThreadProcessId(window,out pid);
   if(pid==(uint)System.Diagnostics.Process.GetCurrentProcess().Id)throw new Exception("Escolha uma janela de outro aplicativo.");
   ShowWindow(window,9);if(!SetForegroundWindow(window))throw new Exception("O Windows impediu o foco. Clique na janela e tente novamente.");
   Target=window.ToInt64();return Title(window);
  }
  static void Activate(){IntPtr w=new IntPtr(Target);if(Target==0||!IsWindow(w))throw new Exception("Primeiro diga focar janela seguido do titulo do aplicativo.");uint pid;GetWindowThreadProcessId(w,out pid);if(pid==(uint)System.Diagnostics.Process.GetCurrentProcess().Id)throw new Exception("Destino invalido.");if(GetForegroundWindow()!=w&&!SetForegroundWindow(w))throw new Exception("Nao consegui ativar a janela de destino.");if(GetForegroundWindow()!=w)throw new Exception("A janela de destino nao esta em foco.");}
  static void Send(INPUT[] input){if(SendInput((uint)input.Length,input,Marshal.SizeOf(typeof(INPUT)))!=(uint)input.Length)throw new Exception("O Windows bloqueou o controle desse aplicativo.");}
  static INPUT Key(ushort key,ushort scan,uint flags){return new INPUT{type=1,value=new UNION{keyboard=new KEYBOARD{key=key,scan=scan,flags=flags}}};}
  public static void Type(string text){Activate();if(text.Length>4000)throw new Exception("Digite no maximo 4000 caracteres por comando.");foreach(char c in text){Send(new[]{Key(0,c,4),Key(0,c,6)});}}
  public static void Press(ushort key,bool control,bool shift,bool alt){Activate();var held=new List<ushort>();try{foreach(ushort mod in new ushort[]{(ushort)(control?17:0),(ushort)(shift?16:0),(ushort)(alt?18:0)})if(mod!=0){Send(new[]{Key(mod,0,0)});held.Add(mod);}Send(new[]{Key(key,0,0),Key(key,0,2)});}finally{held.Reverse();foreach(ushort mod in held)Send(new[]{Key(mod,0,2)});}}
  public static void Move(int x,int y){if(!OnDisplay(x,y,Displays()))throw new Exception("Coordenadas fora dos monitores.");if(!SetPhysical(x,y))throw new Exception("Nao consegui mover o mouse.");}
  public static void Click(bool right,bool twice){Activate();for(int n=0;n<(twice?2:1);n++){Send(new[]{new INPUT{type=0,value=new UNION{mouse=new MOUSE{flags=(uint)(right?8:2)}}},new INPUT{type=0,value=new UNION{mouse=new MOUSE{flags=(uint)(right?16:4)}}}});}}
  public static void Scroll(int amount){Activate();Send(new[]{new INPUT{type=0,value=new UNION{mouse=new MOUSE{flags=0x800,data=unchecked((uint)amount)}}}});}
  public static void Window(int command){Activate();ShowWindow(new IntPtr(Target),command);}
 }
}
