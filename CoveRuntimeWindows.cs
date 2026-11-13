using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
namespace CoveApp {
 public static class RuntimeWindows {
  delegate bool Callback(IntPtr window,IntPtr parameter);
  [DllImport("user32.dll")] static extern bool EnumWindows(Callback callback,IntPtr parameter);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr window,StringBuilder value,int count);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr window,uint message,IntPtr wparam,IntPtr lparam);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr window,int command);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
  [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr window);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr window,IntPtr after,int x,int y,int width,int height,uint flags);
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern bool AttachThreadInput(uint from,uint to,bool attach);
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  public static bool RevealConversation(int pid){
   bool shown=false;
   foreach(long handle in Handles(pid,"Conversa com Cove")){
    var window=new IntPtr(handle);ShowWindow(window,9);
    // Display even when Windows refuses focus transfer to a background worker.
    // The application's own foreground pulse restores normal stacking shortly.
    SetWindowPos(window,new IntPtr(-1),0,0,0,0,0x43);
    uint owner;uint foregroundThread=GetWindowThreadProcessId(GetForegroundWindow(),out owner),current=GetCurrentThreadId();bool attached=false;
    try{if(foregroundThread!=0&&foregroundThread!=current)attached=AttachThreadInput(current,foregroundThread,true);BringWindowToTop(window);shown=SetForegroundWindow(window)||shown;}
    finally{if(attached)AttachThreadInput(current,foregroundThread,false);}
   }
   return shown;
  }
  static string Title(IntPtr window){var value=new StringBuilder(256);GetWindowText(window,value,value.Capacity);return value.ToString();}
  public static long[] Handles(int pid,string title){var result=new List<long>();EnumWindows((w,p)=>{uint owner;GetWindowThreadProcessId(w,out owner);if(owner==(uint)pid&&Title(w)==title)result.Add(w.ToInt64());return true;},IntPtr.Zero);return result.ToArray();}
  public static bool CloseCove(int pid){bool sent=false;foreach(long handle in Handles(pid,"Cove"))sent=PostMessage(new IntPtr(handle),0x0010,IntPtr.Zero,IntPtr.Zero)||sent;return sent;}
 }
}
