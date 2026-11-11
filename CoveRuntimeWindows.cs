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
  static string Title(IntPtr window){var value=new StringBuilder(256);GetWindowText(window,value,value.Capacity);return value.ToString();}
  public static long[] Handles(int pid,string title){var result=new List<long>();EnumWindows((w,p)=>{uint owner;GetWindowThreadProcessId(w,out owner);if(owner==(uint)pid&&Title(w)==title)result.Add(w.ToInt64());return true;},IntPtr.Zero);return result.ToArray();}
  public static bool CloseCove(int pid){bool sent=false;foreach(long handle in Handles(pid,"Cove"))sent=PostMessage(new IntPtr(handle),0x0010,IntPtr.Zero,IntPtr.Zero)||sent;return sent;}
 }
}
