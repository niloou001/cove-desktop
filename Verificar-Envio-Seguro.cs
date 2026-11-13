using System;using CoveApp;
namespace CoveTests {
 public static class MessageWorkflow {
  public static string Run(){
   int probes=0,restores=0;
   if(!DiscordCall.RecoverClickTarget(()=>++probes==3,()=>restores++,()=>{})||probes!=3||restores!=2)throw new Exception("Covered Discord target was not recovered before clicking");
   probes=0;restores=0;
   if(DiscordCall.RecoverClickTarget(()=>{probes++;return false;},()=>restores++,()=>{})||probes!=3||restores!=2)throw new Exception("Permanent overlay must stop after bounded recovery");
   restores=0;bool recoveryCancelled=false;
   try{DiscordCall.RecoverClickTarget(()=>false,()=>restores++,()=>{throw new OperationCanceledException("Esc");});}catch(OperationCanceledException){recoveryCancelled=true;}
   if(!recoveryCancelled||restores!=0)throw new Exception("Overlay recovery ignored cancellation");
   bool restoreCancelled=false;
   try{DiscordCall.RecoverClickTarget(()=>false,()=>{throw new OperationCanceledException("User moved mouse");},()=>{});}catch(OperationCanceledException){restoreCancelled=true;}
   if(!restoreCancelled)throw new Exception("Restore cancellation was swallowed");
   bool fieldFocused=false;string unfocusedDraft="";int focusFirstSends=0;
   Messaging.PrepareAndSend("Focus first",()=>true,()=>{if(!fieldFocused)throw new InvalidOperationException("No text until focus");return unfocusedDraft;},()=>fieldFocused=true,value=>unfocusedDraft=value,()=>{},()=>focusFirstSends++);
   if(focusFirstSends!=1||unfocusedDraft!="Focus first")throw new Exception("Unselected field must be focused before reading or writing");
   int controlReads=0;
   string recovered=Messaging.AwaitControl(()=>{controlReads++;if(controlReads==1)throw new System.Windows.Automation.ElementNotAvailableException();if(controlReads==2)throw new System.Runtime.InteropServices.COMException();return "fresh";},()=>{},1000);
   if(recovered!="fresh"||controlReads!=3)throw new Exception("Recreated controls were not retried");
   bool controlCancelled=false;
   try{Messaging.AwaitControl<string>(()=>{throw new OperationCanceledException();},()=>{},1000);}catch(OperationCanceledException){controlCancelled=true;}
   if(!controlCancelled)throw new Exception("Recovery swallowed cancellation");
   string draft="";int sends=0,writes=0,checks=0;bool recipient=true;
   Action focus=()=>{};Action check=()=>{checks++;};
   Action<string> write=text=>{draft=text;writes++;};Action send=()=>{sends++;};
   Messaging.PrepareAndSend("Oi, Ester!",()=>recipient,()=>draft,focus,write,check,send);
   if(sends!=1||writes!=1||draft!="Oi, Ester!"||checks<3)throw new Exception("Exact one-shot send failed");
   draft="";sends=0;writes=0;int focusAttempts=0;bool focused=false;
   Messaging.PrepareAndSend("Foco recuperado",()=>true,()=>draft,()=>Messaging.AcquireFocus(()=>focused,number=>{focusAttempts++;if(focusAttempts==3)focused=true;},check,4,0),write,check,send);
   if(focusAttempts!=3||writes!=1||sends!=1)throw new Exception("Focus retry must not retype or resend");
   draft="";sends=0;writes=0;focusAttempts=0;bool focusRejected=false;
   try{Messaging.PrepareAndSend("Nao enviar",()=>true,()=>draft,()=>Messaging.AcquireFocus(()=>false,number=>{focusAttempts++;},check,4,0),write,check,send);}catch{focusRejected=true;}
   if(!focusRejected||focusAttempts!=4||writes!=0||sends!=0)throw new Exception("Focus failure must stop before writing/sending");
   int cancelledAttempts=0;bool focusCancelled=false;
   try{Messaging.AcquireFocus(()=>false,number=>{cancelledAttempts++;throw new OperationCanceledException("User stopped");},check,4,0);}catch(OperationCanceledException){focusCancelled=true;}
   if(!focusCancelled||cancelledAttempts!=1)throw new Exception("Cancellation must not be retried");
   draft="";sends=0;writes=0;int reads=0;
   Messaging.PrepareAndSend("Delayed text",()=>true,()=>{reads++;return reads<4?"":draft;},focus,write,check,send);
   if(sends!=1||writes!=1||reads<4)throw new Exception("Delayed UI update must wait without retyping or resending");
   sends=0;writes=0;draft="Rascunho do usuario";bool rejected=false;
   try{Messaging.PrepareAndSend("Novo texto",()=>true,()=>draft,focus,write,check,send);}catch{rejected=true;}
   if(!rejected||sends!=0||writes!=0||draft!="Rascunho do usuario")throw new Exception("User draft overwritten");
   string backup=null;draft="Rascunho do usuario";sends=0;writes=0;
   Messaging.PrepareAndSend("Novo recado",()=>true,()=>draft,focus,write,check,send,old=>{backup=old;});
   if(backup!="Rascunho do usuario"||draft!="Novo recado"||writes!=1||sends!=1)throw new Exception("Existing draft not backed up/replaced once");
   draft="Mesmo recado";sends=0;writes=0;backup=null;
   Messaging.PrepareAndSend("Mesmo recado",()=>true,()=>draft,focus,write,check,send,old=>{backup=old;});
   if(writes!=0||sends!=1||backup!=null)throw new Exception("Existing desired draft should be reused");
   draft="Rascunho protegido";sends=0;writes=0;rejected=false;
   try{Messaging.PrepareAndSend("Novo recado",()=>true,()=>draft,focus,write,check,send,old=>{throw new Exception("Backup unavailable");});}catch{rejected=true;}
   if(!rejected||draft!="Rascunho protegido"||writes!=0||sends!=0)throw new Exception("Draft cleared before successful backup");
   if(Messaging.NormalizeDraft("\u200B\r\n\uFEFF")!=""||Messaging.NormalizeDraft("texto real")!="texto real")throw new Exception("Phantom empty draft not normalized");
   sends=0;writes=0;
   draft="";recipient=false;rejected=false;
   try{Messaging.PrepareAndSend("Oi",()=>recipient,()=>draft,focus,write,check,send);}catch{rejected=true;}
   if(!rejected||sends!=0||writes!=0)throw new Exception("Wrong contact accepted");
   recipient=true;rejected=false;draft="";
   try{Messaging.PrepareAndSend("Oi",()=>recipient,()=>draft,focus,text=>{draft=text;recipient=false;},check,send);}catch{rejected=true;}
   if(!rejected||sends!=0)throw new Exception("Changed contact received a message");
   rejected=false;draft="";
   try{Messaging.PrepareAndSend("Oi",()=>true,()=>draft,focus,text=>{draft="other text";},check,send);}catch{rejected=true;}
   if(!rejected||sends!=0)throw new Exception("Wrong draft sent");
   draft="";int attempts=0;rejected=false;
   try{Messaging.PrepareAndSend("Oi",()=>true,()=>draft,focus,write,check,()=>{attempts++;throw new Exception("Delayed UI");});}catch{rejected=true;}
   if(!rejected||attempts!=1)throw new Exception("Send retried");
   if(Messaging.ContactResult("Ester",new[]{"Ester","grupo"},"Ester"))throw new Exception("Group accepted");
   if(Messaging.ContactResult("Esther",new[]{"Esther"},"Ester"))throw new Exception("Near contact accepted");
   if(Messaging.ValidateMessage("oi\r\nEster")!="oi Ester")throw new Exception("Newlines could send early");
   if(Messaging.IsComposer("Pesquisar contatos","","WhatsApp"))throw new Exception("Search accepted as composer");
   return "OK: one send, exact content, contact checked twice, existing drafts preserved, changed recipient/wrong draft blocked, failed send not retried, groups excluded, search field excluded. All effects simulated.";
  }
 }
}
