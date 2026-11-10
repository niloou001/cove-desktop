using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Security.Cryptography;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using System.Diagnostics;
using System.Web.Script.Serialization;

namespace CoveApp {
 // Official Sign in with ChatGPT public-client flow. No browser cookies or
 // credentials belonging to Codex or any other app are read.
 public sealed class ChatGPTAccount {
  const string Resource="https://api.openai.com/v1";
  const string TokenEndpoint="https://auth.openai.com/api/accounts/oauth/token";
  readonly string directory,hostId;
  readonly SemaphoreSlim gate=new SemaphoreSlim(1,1);
  Dictionary<string,object> profile;
  public ChatGPTAccount(string path) {
   directory=path;Directory.CreateDirectory(path);
   string hostPath=Path.Combine(path,"host.txt");
   if(!File.Exists(hostPath)) {
    try { using(var f=new FileStream(hostPath,FileMode.CreateNew,FileAccess.Write,FileShare.None)) { var b=Encoding.UTF8.GetBytes("urn:uuid:"+Guid.NewGuid());f.Write(b,0,b.Length); } }
    catch(IOException) { if(!File.Exists(hostPath))throw; }
   }
   hostId=File.ReadAllText(hostPath).Trim();profile=Load();
  }
  static JavaScriptSerializer Json(){return new JavaScriptSerializer{MaxJsonLength=4000000};}
  static Dictionary<string,object> Object(string json){return Json().DeserializeObject(json) as Dictionary<string,object>;}
  static string Str(Dictionary<string,object> map,string key){object o;return map!=null&&map.TryGetValue(key,out o)&&o is string?(string)o:"";}
  static long Now(){return DateTimeOffset.UtcNow.ToUnixTimeSeconds();}
  static string B64(byte[] b){return Convert.ToBase64String(b).TrimEnd('=').Replace('+','-').Replace('/','_');}
  static byte[] Un64(string s){s=s.Replace('-','+').Replace('_','/');return Convert.FromBase64String(s.PadRight((s.Length+3)/4*4,'='));}
  static string Random(){var b=new byte[32];using(var r=RandomNumberGenerator.Create())r.GetBytes(b);return B64(b);}
  static string Query(Dictionary<string,string> values){var b=new StringBuilder();foreach(var kv in values){if(b.Length>0)b.Append('&');b.Append(Uri.EscapeDataString(kv.Key)).Append('=').Append(Uri.EscapeDataString(kv.Value));}return b.ToString();}
  public static Dictionary<string,string> ParseQuery(string text) {
   var result=new Dictionary<string,string>();
   foreach(string part in text.TrimStart('?').Split('&')) {
    if(part.Length==0)continue;var pair=part.Split(new[]{'='},2);
    string k=Uri.UnescapeDataString(pair[0].Replace('+',' '));
    if(result.ContainsKey(k))throw new Exception("Parametro duplicado no retorno do login.");
    result[k]=pair.Length>1?Uri.UnescapeDataString(pair[1].Replace('+',' ')):"";
   }return result;
  }
  Dictionary<string,object> Load() {
   string file=Path.Combine(directory,"account.dat");if(!File.Exists(file))return new Dictionary<string,object>();
   byte[] bytes=null;
   try{bytes=ProtectedData.Unprotect(File.ReadAllBytes(file),null,DataProtectionScope.CurrentUser);return Object(Encoding.UTF8.GetString(bytes));}
   catch{throw new Exception("Nao foi possivel ler a conexao protegida do Cove neste usuario do Windows.");}
   finally{if(bytes!=null)Array.Clear(bytes,0,bytes.Length);}
  }
  void Save(Dictionary<string,object> data) {
   string file=Path.Combine(directory,"account.dat"),temp=Path.Combine(directory,Guid.NewGuid().ToString("N")+".tmp");
   byte[] raw=Encoding.UTF8.GetBytes(Json().Serialize(data));
   try {
    File.WriteAllBytes(temp,ProtectedData.Protect(raw,null,DataProtectionScope.CurrentUser));
    if(File.Exists(file))File.Replace(temp,file,null);else File.Move(temp,file);
    profile=data;
   }finally{Array.Clear(raw,0,raw.Length);if(File.Exists(temp))File.Delete(temp);}
  }
  public bool Connected {get{return Str(profile,"access_token").Length>0&&HasPermission(Str(profile,"scope"));}}
  public string AccountLabel {get{return Str(profile,"email").Length>0?Str(profile,"email"):"Conta ChatGPT";}}
  public static bool HasPermission(string scope){return Array.IndexOf(scope.Split(' '),"chatgpt.tokens.use.direct")>=0;}
  static HttpClient Client(){ServicePointManager.SecurityProtocol=SecurityProtocolType.Tls12;return new HttpClient{Timeout=TimeSpan.FromSeconds(40)};}
  static async Task<Dictionary<string,object>> PostToken(Dictionary<string,string> form,CancellationToken token) {
   using(var http=Client())using(var body=new FormUrlEncodedContent(form))using(var response=await http.PostAsync(TokenEndpoint,body,token).ConfigureAwait(false)) {
    if(!response.IsSuccessStatusCode)throw new Exception("A OpenAI nao concluiu o login ou a renovacao. Entre novamente pelo botao Continuar com ChatGPT.");
    return Object(await response.Content.ReadAsStringAsync().ConfigureAwait(false));
   }
  }
  static async Task<string> GetText(HttpClient http,string url,CancellationToken token) {
   using(var response=await http.GetAsync(url,token).ConfigureAwait(false)) {
    if(!response.IsSuccessStatusCode)throw new Exception("Nao foi possivel verificar a identidade com a OpenAI.");
    return await response.Content.ReadAsStringAsync().ConfigureAwait(false);
   }
  }
  public static void CheckClaims(Dictionary<string,object> claims,string clientId,string nonce,long now) {
   if(Str(claims,"iss")!="https://auth.openai.com")throw new Exception("Emissor do login invalido.");
   object audience;bool match=false;
   if(claims.TryGetValue("aud",out audience)) {
    if(audience is string)match=(string)audience==clientId;
    else if(audience is object[])foreach(object a in (object[])audience)if(a is string&&(string)a==clientId)match=true;
   }
   if(!match)throw new Exception("Login destinado a outro aplicativo.");
   object exp;if(!claims.TryGetValue("exp",out exp)||Convert.ToInt64(exp)<=now)throw new Exception("Identidade do login expirou.");
   object nbf;if(claims.TryGetValue("nbf",out nbf)&&Convert.ToInt64(nbf)>now+60)throw new Exception("Identidade do login ainda nao e valida.");
   if(Str(claims,"sub").Length==0)throw new Exception("Login sem identidade verificavel.");
   if(nonce!=null&&Str(claims,"nonce")!=nonce)throw new Exception("Retorno do login nao corresponde a esta tentativa.");
  }
  static async Task<Dictionary<string,object>> VerifyId(string jwt,string clientId,string nonce,CancellationToken token) {
   string[] pieces=jwt.Split('.');if(pieces.Length!=3)throw new Exception("Identidade do login invalida.");
   var head=Object(Encoding.UTF8.GetString(Un64(pieces[0])));
   if(Str(head,"alg")!="RS256")throw new Exception("Algoritmo de identidade nao suportado; login interrompido.");
   var claims=Object(Encoding.UTF8.GetString(Un64(pieces[1])));
   using(var http=Client()) {
    var discovery=Object(await GetText(http,"https://auth.openai.com/.well-known/openid-configuration",token).ConfigureAwait(false));
    if(Str(discovery,"issuer")!="https://auth.openai.com")throw new Exception("Configuracao de identidade invalida.");
    var uri=new Uri(Str(discovery,"jwks_uri"));
    if(uri.Scheme!="https"||uri.Host!="auth.openai.com"||!uri.IsDefaultPort)throw new Exception("Endereco de verificacao inesperado.");
    var jwks=Object(await GetText(http,uri.AbsoluteUri,token).ConfigureAwait(false));object keys;bool valid=false;
    if(jwks.TryGetValue("keys",out keys))foreach(var item in (object[])keys) {
     var key=item as Dictionary<string,object>;
     if(Str(key,"kid")!=Str(head,"kid")||Str(key,"kty")!="RSA")continue;
     if(Str(key,"use").Length>0&&Str(key,"use")!="sig")continue;
     using(var rsa=new RSACryptoServiceProvider()) {
      rsa.PersistKeyInCsp=false;rsa.ImportParameters(new RSAParameters{Modulus=Un64(Str(key,"n")),Exponent=Un64(Str(key,"e"))});
      valid=rsa.VerifyData(Encoding.ASCII.GetBytes(pieces[0]+"."+pieces[1]),CryptoConfig.MapNameToOID("SHA256"),Un64(pieces[2]));
     }if(valid)break;
    }
    if(!valid)throw new Exception("A assinatura da identidade nao foi confirmada.");
   }
   CheckClaims(claims,clientId,nonce,Now());return claims;
  }
  static void BrowserReply(NetworkStream stream,bool ok) {
   string html="<!doctype html><meta charset=utf-8><title>Cove</title><body style='background:#0e1927;color:#e6eef8;font:18px system-ui;padding:60px'><h1>Cove</h1><p>"+(ok?"Login recebido. Volte ao Cove para conferir a conexao.":"Este retorno de login nao foi aceito. Volte ao Cove.")+"</p>";
   byte[] body=Encoding.UTF8.GetBytes(html),head=Encoding.ASCII.GetBytes("HTTP/1.1 "+(ok?"200 OK":"400 Bad Request")+"\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: "+body.Length+"\r\n\r\n");
   stream.Write(head,0,head.Length);stream.Write(body,0,body.Length);
  }
  public async Task<string> SignIn(CancellationToken cancellation) {
   await gate.WaitAsync(cancellation).ConfigureAwait(false);
   try {
    using(var timeout=CancellationTokenSource.CreateLinkedTokenSource(cancellation)) {
     timeout.CancelAfter(TimeSpan.FromMinutes(3));var token=timeout.Token;
     profile=Load();string savedId=Str(profile,"client_id"),savedSub=Str(profile,"subject");
     bool fresh=savedId.Length==0;string verifier=Random(),state=Random(),nonce=Random(),challenge;
     using(var sha=SHA256.Create())challenge=B64(sha.ComputeHash(Encoding.ASCII.GetBytes(verifier)));
     var listener=new TcpListener(IPAddress.Loopback,0);listener.Start();
     string redirect="http://127.0.0.1:"+((IPEndPoint)listener.LocalEndpoint).Port+"/auth/callback";
     try {
      using(token.Register(()=>listener.Stop())) {
       var query=new Dictionary<string,string>{{"client_id",fresh?"dynamic_agent_client":savedId},{"ext_agent_host_id",hostId},{"response_type","code"},{"redirect_uri",redirect},{"scope","openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"},{"resource",Resource},{"state",state},{"nonce",nonce},{"code_challenge_method","S256"},{"code_challenge",challenge}};
       if(fresh)query["agent_name_hint"]="Cove";
       else {if(Str(profile,"id_token").Length>0)query["id_token_hint"]=Str(profile,"id_token");if(Str(profile,"email").Length>0)query["login_hint"]=Str(profile,"email");}
       try{Process.Start(new ProcessStartInfo("https://auth.openai.com/api/accounts/authorize?"+Query(query)){UseShellExecute=true});}
       catch{throw new Exception("Nao foi possivel abrir o navegador. Confira o navegador padrao do Windows e tente novamente.");}
       Dictionary<string,string> callback=null;
       while(callback==null) {
        token.ThrowIfCancellationRequested();
        using(var client=await listener.AcceptTcpClientAsync().ConfigureAwait(false))
        using(token.Register(()=>client.Close()))
        using(var stream=client.GetStream()) {
         var buffer=new byte[8192];int n=0;
         using(var readTimeout=CancellationTokenSource.CreateLinkedTokenSource(token)) {
          readTimeout.CancelAfter(TimeSpan.FromSeconds(5));
          try{while(n<buffer.Length){int count=await stream.ReadAsync(buffer,n,buffer.Length-n,readTimeout.Token).ConfigureAwait(false);if(count==0)break;n+=count;if(Encoding.ASCII.GetString(buffer,0,n).Contains("\r\n\r\n"))break;}}catch(OperationCanceledException){token.ThrowIfCancellationRequested();continue;}
         }
         string line=Encoding.ASCII.GetString(buffer,0,n).Split(new[]{"\r\n"},StringSplitOptions.None)[0];
         string[] request=line.Split(' ');Uri uri;
         if(request.Length!=3||request[0]!="GET"||!request[1].StartsWith("/auth/callback?")||!Uri.TryCreate("http://127.0.0.1"+request[1],UriKind.Absolute,out uri)){BrowserReply(stream,false);continue;}
         var parsed=ParseQuery(uri.Query);string gotState;
         if(!parsed.TryGetValue("state",out gotState)||gotState!=state){BrowserReply(stream,false);continue;}
         BrowserReply(stream,true);callback=parsed;
        }
       }
       if(callback.ContainsKey("error"))throw new Exception("Login cancelado ou permissao nao autorizada. Nenhuma conexao foi ativada.");
       string issuedId;
       if(fresh) {
        if(!callback.TryGetValue("client_id",out issuedId)||issuedId.Length==0||issuedId=="dynamic_agent_client")throw new Exception("A OpenAI nao concluiu o registro do Cove.");
        // Retain registration before exchanging the one-time code.
        profile["client_id"]=issuedId;Save(profile);
       }else {issuedId=savedId;if(callback.ContainsKey("client_id")&&callback["client_id"]!=savedId)throw new Exception("O retorno pertence a outra conexao.");}
       string code;if(!callback.TryGetValue("code",out code)||code.Length==0)throw new Exception("Login retornou sem codigo de autorizacao.");
       var tokens=await PostToken(new Dictionary<string,string>{{"grant_type","authorization_code"},{"client_id",issuedId},{"code",code},{"code_verifier",verifier},{"redirect_uri",redirect},{"resource",Resource}},token).ConfigureAwait(false);
       var identity=await VerifyId(Str(tokens,"id_token"),issuedId,nonce,token).ConfigureAwait(false);
       if(savedSub.Length>0&&Str(identity,"sub")!=savedSub)throw new Exception("A conta retornada difere da conta registrada no Cove.");
       if(!HasPermission(Str(tokens,"scope")))throw new Exception("O login nao autorizou o uso do plano ChatGPT. A disponibilidade depende da conta e do plano.");
       Save(BuildProfile(tokens,identity,issuedId,profile));
       return AccountLabel;
      }
     }catch(ObjectDisposedException){token.ThrowIfCancellationRequested();throw;}
      catch(SocketException){token.ThrowIfCancellationRequested();throw;}
      finally{listener.Stop();}
    }
   }finally{gate.Release();}
  }
  static Dictionary<string,object> BuildProfile(Dictionary<string,object> tokens,Dictionary<string,object> identity,string id,Dictionary<string,object> previous) {
   if(Str(tokens,"access_token").Length==0)throw new Exception("Login sem credencial de acesso.");
   string kind=Str(tokens,"token_type");if(kind.Length>0&&!kind.Equals("Bearer",StringComparison.OrdinalIgnoreCase))throw new Exception("Tipo de credencial inesperado.");
   var result=new Dictionary<string,object>(previous);
   result["client_id"]=id;result["subject"]=Str(identity,"sub");result["email"]=Str(identity,"email");
   result["access_token"]=Str(tokens,"access_token");result["scope"]=Str(tokens,"scope");
   if(Str(tokens,"refresh_token").Length>0)result["refresh_token"]=Str(tokens,"refresh_token");
   if(Str(tokens,"id_token").Length>0)result["id_token"]=Str(tokens,"id_token");
   object expiry;result["expires_at"]=Now()+(tokens.TryGetValue("expires_in",out expiry)?Convert.ToInt64(expiry):3600);return result;
  }
  async Task<string> AccessToken(CancellationToken token) {
   profile=Load();if(!Connected)throw new Exception("Conecte sua conta em Ajustes > Continuar com ChatGPT.");
   object expiry;
   if(profile.TryGetValue("expires_at",out expiry)&&Convert.ToInt64(expiry)>Now()+90)return Str(profile,"access_token");
   // Serialize rotation across Cove processes without reading other apps' tokens.
   FileStream rotation=null;DateTime deadline=DateTime.UtcNow.AddSeconds(8);
   while(rotation==null){try{rotation=new FileStream(Path.Combine(directory,"refresh.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None);}catch(IOException){if(DateTime.UtcNow>=deadline)throw new Exception("Outra janela do Cove esta renovando o login. Tente novamente.");}if(rotation==null)await Task.Delay(100,token).ConfigureAwait(false);}
   using(rotation) {
    profile=Load();if(profile.TryGetValue("expires_at",out expiry)&&Convert.ToInt64(expiry)>Now()+90)return Str(profile,"access_token");
    if(Str(profile,"refresh_token").Length==0)throw new Exception("Entre novamente em Ajustes > Continuar com ChatGPT.");
    var tokens=await PostToken(new Dictionary<string,string>{{"grant_type","refresh_token"},{"client_id",Str(profile,"client_id")},{"refresh_token",Str(profile,"refresh_token")},{"resource",Resource}},token).ConfigureAwait(false);
    if(!tokens.ContainsKey("scope"))tokens["scope"]=Str(profile,"scope");
    if(!HasPermission(Str(tokens,"scope")))throw new Exception("Permissao do plano removida. Entre novamente com ChatGPT.");
    var identity=new Dictionary<string,object>{{"sub",Str(profile,"subject")},{"email",Str(profile,"email")}};
    if(Str(tokens,"id_token").Length>0){identity=await VerifyId(Str(tokens,"id_token"),Str(profile,"client_id"),null,token).ConfigureAwait(false);if(Str(identity,"sub")!=Str(profile,"subject"))throw new Exception("Identidade mudou durante a renovacao.");}
    Save(BuildProfile(tokens,identity,Str(profile,"client_id"),profile));return Str(profile,"access_token");
   }
  }
  public async Task<string> Ask(string body,CancellationToken token) {
   await gate.WaitAsync(token).ConfigureAwait(false);
   try {
    string access=await AccessToken(token).ConfigureAwait(false);
    using(var http=Client()) {
     http.DefaultRequestHeaders.Authorization=new AuthenticationHeaderValue("Bearer",access);
     var catalog=Object(await GetText(http,Resource+"/models",token).ConfigureAwait(false));object models;string chosen="";
     if(catalog.TryGetValue("models",out models))foreach(var item in (object[])models){var model=item as Dictionary<string,object>;if(Str(model,"visibility")=="list"&&Str(model,"slug").Length>0){chosen=Str(model,"slug");break;}}
     if(chosen.Length==0)throw new Exception("Nenhum modelo disponivel para esta conexao ChatGPT.");
     var request=Object(body);request["model"]=chosen;request["stream"]=true;request["store"]=false;
     // Avoid unsupported API-only options for account-specific models.
     request.Remove("max_output_tokens");
     using(var message=new HttpRequestMessage(HttpMethod.Post,Resource+"/responses")) {
      message.Content=new StringContent(Json().Serialize(request),Encoding.UTF8,"application/json");
      using(var response=await http.SendAsync(message,HttpCompletionOption.ResponseHeadersRead,token).ConfigureAwait(false)) {
       if(!response.IsSuccessStatusCode){if((int)response.StatusCode==429)throw new Exception("Limite do plano ChatGPT atingido para o Cove. Confira o uso e a permissao do app nos Ajustes do ChatGPT.");throw new Exception("ChatGPT recusou a pergunta (HTTP "+(int)response.StatusCode+"). Confira a conexao e as permissoes do Cove.");}
       using(var stream=await response.Content.ReadAsStreamAsync().ConfigureAwait(false))
       using(var reader=new StreamReader(stream,Encoding.UTF8))
       using(token.Register(()=>stream.Close())) {
        var data=new StringBuilder();var output=new StringBuilder();bool completed=false;string line;
        while((line=await reader.ReadLineAsync().ConfigureAwait(false))!=null) {
         token.ThrowIfCancellationRequested();
         if(line.Length==0){if(data.Length>0){ProcessEvent(data.ToString(),output,ref completed);data.Clear();}if(completed)break;}
         else if(line.StartsWith("data:")){if(data.Length>0)data.Append('\n');data.Append(line.Substring(5).TrimStart());}
        }
        if(!completed&&data.Length>0)ProcessEvent(data.ToString(),output,ref completed);
        if(!completed)throw new Exception("A resposta do ChatGPT foi interrompida antes de terminar.");
        if(output.Length==0)throw new Exception("ChatGPT terminou sem uma resposta de texto.");return output.ToString();
       }
      }
     }
    }
   }finally{gate.Release();}
  }
  public static void ProcessEvent(string json,StringBuilder output,ref bool completed) {
   if(json=="[DONE]")return;var data=Object(json);string kind=Str(data,"type");
   if(kind=="response.output_text.delta")output.Append(Str(data,"delta"));
   if(kind=="response.completed")completed=true;
   if(kind=="response.failed"||kind=="error")throw new Exception("ChatGPT nao concluiu a resposta. Confira os limites e o acesso do Cove nos Ajustes do ChatGPT.");
   if(kind=="response.incomplete")throw new Exception("A resposta do ChatGPT ficou incompleta. Tente uma pergunta mais curta.");
  }
  public async Task<string> Disconnect(CancellationToken token) {
   await gate.WaitAsync(token).ConfigureAwait(false);
   try {
    profile=Load();bool revoked=false;
    try {
     if(Str(profile,"refresh_token").Length>0)using(var http=Client()) {
      var discovery=Object(await GetText(http,"https://auth.openai.com/.well-known/openid-configuration",token).ConfigureAwait(false));
      var uri=new Uri(Str(discovery,"revocation_endpoint"));
      if(uri.Scheme!="https"||uri.Host!="auth.openai.com"||!uri.IsDefaultPort)throw new Exception("Endereco de revogacao inesperado.");
      using(var body=new FormUrlEncodedContent(new Dictionary<string,string>{{"token",Str(profile,"refresh_token")},{"token_type_hint","refresh_token"},{"client_id",Str(profile,"client_id")}}))
      using(var response=await http.PostAsync(uri,body,token).ConfigureAwait(false))revoked=response.StatusCode==HttpStatusCode.OK;
     }else revoked=true;
    }catch{}
    foreach(string key in new[]{"access_token","refresh_token","id_token","scope","expires_at"})profile.Remove(key);
    Save(profile);return revoked?"Conta desconectada do Cove.":"Conta desconectada localmente. Nao foi possivel confirmar a revogacao; remova tambem o acesso do Cove nos Ajustes do ChatGPT.";
   }finally{gate.Release();}
  }
 }
}
