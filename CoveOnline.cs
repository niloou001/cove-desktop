using System;
using System.Collections.Generic;
using System.Globalization;
using System.Net;
using System.Net.Http;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Xml;
using System.IO;
namespace CoveApp {
 public static class Online {
  static readonly HttpClient http=CreateClient();
  static readonly object gate=new object();
  sealed class Cached { public string Text;public DateTime Until; }
  static readonly Dictionary<string,Cached> cache=new Dictionary<string,Cached>();
  static HttpClient CreateClient(){ServicePointManager.SecurityProtocol|=SecurityProtocolType.Tls12;var client=new HttpClient{Timeout=TimeSpan.FromSeconds(8)};client.DefaultRequestHeaders.UserAgent.ParseAdd("CoveDesktop/1.0");return client;}
  static string CachedText(string key){lock(gate){Cached value;return cache.TryGetValue(key,out value)&&value.Until>DateTime.UtcNow?value.Text:null;}}
  static string Remember(string key,string text,int seconds){lock(gate){if(cache.Count>40)cache.Clear();cache[key]=new Cached{Text=text,Until=DateTime.UtcNow.AddSeconds(seconds)};}return text;}
  static Dictionary<string,object> Json(string text){return new JavaScriptSerializer{MaxJsonLength=2000000}.DeserializeObject(text) as Dictionary<string,object>;}
  static string Str(Dictionary<string,object> data,string key){object value;return data!=null&&data.TryGetValue(key,out value)?Convert.ToString(value,CultureInfo.InvariantCulture):"";}
  static async Task<string> Get(string url,CancellationToken token){using(var response=await http.GetAsync(url,token).ConfigureAwait(false)){response.EnsureSuccessStatusCode();if(response.Content.Headers.ContentLength>2000000)throw new Exception("Resposta online muito grande.");return await response.Content.ReadAsStringAsync().ConfigureAwait(false);}}
  public static string FormatWeather(string city,string json){
   var data=Json(json);object raw;if(data==null||!data.TryGetValue("current",out raw))throw new Exception("Temperatura indisponivel na fonte.");var current=raw as Dictionary<string,object>;double temperature;
   if(!Double.TryParse(Str(current,"temperature_2m"),NumberStyles.Float,CultureInfo.InvariantCulture,out temperature)||Double.IsNaN(temperature)||Double.IsInfinity(temperature))throw new Exception("Temperatura invalida na fonte.");
   DateTime stamp;if(!DateTime.TryParse(Str(current,"time"),CultureInfo.InvariantCulture,DateTimeStyles.None,out stamp))throw new Exception("Horario da temperatura indisponivel.");
   object offsetRaw;double offset;if(!data.TryGetValue("utc_offset_seconds",out offsetRaw)||!Double.TryParse(Convert.ToString(offsetRaw,CultureInfo.InvariantCulture),NumberStyles.Float,CultureInfo.InvariantCulture,out offset))throw new Exception("Fuso horario da temperatura indisponivel.");
   var utc=DateTime.SpecifyKind(stamp,DateTimeKind.Unspecified).AddSeconds(-offset);
   if(Math.Abs((DateTime.UtcNow-utc).TotalHours)>2)throw new Exception("A fonte retornou uma temperatura antiga. Tente novamente.");
   return "Em "+city+", a temperatura e "+temperature.ToString("0.#",CultureInfo.GetCultureInfo("pt-BR"))+" graus Celsius. Dados das "+stamp.ToString("HH:mm")+" no local. Fonte: Open-Meteo (estimativa meteorologica).";
  }
  public static Task<string> Weather(string city,CancellationToken token){return WeatherCore(city,token);}
  static async Task<string> WeatherCore(string city,CancellationToken token){
   string key="weather:"+city.Trim().ToLowerInvariant(),saved=CachedText(key);if(saved!=null)return saved;
   try{
    var geo=Json(await Get("https://geocoding-api.open-meteo.com/v1/search?name="+Uri.EscapeDataString(city)+"&count=5&language=pt&format=json",token).ConfigureAwait(false));object raw;
    if(geo==null||!geo.TryGetValue("results",out raw))return "Nao encontrei a cidade "+city+". Diga cidade e estado.";
    var candidates=new List<Dictionary<string,object>>();
    foreach(object item in (object[])raw){var place=item as Dictionary<string,object>;if(place!=null)candidates.Add(place);}
    if(candidates.Count==0)return "Nao encontrei essa cidade e regiao. Diga o nome completo do estado depois da cidade.";
    if(candidates.Count>1){var names=new List<string>();foreach(var place in candidates)names.Add(Str(place,"name")+", "+Str(place,"admin1")+", "+Str(place,"country"));return "Encontrei mais de um lugar. Diga a cidade e o estado: "+String.Join("; ",names)+".";}
    var chosen=candidates[0];string label=Str(chosen,"name")+", "+Str(chosen,"admin1")+", "+Str(chosen,"country");
    string weather=await Get("https://api.open-meteo.com/v1/forecast?latitude="+Uri.EscapeDataString(Str(chosen,"latitude"))+"&longitude="+Uri.EscapeDataString(Str(chosen,"longitude"))+"&current=temperature_2m&timezone=auto",token).ConfigureAwait(false);
    return Remember(key,FormatWeather(label,weather),60);
   }catch(OperationCanceledException){if(token.IsCancellationRequested)throw;return "A consulta da temperatura demorou demais. Tente novamente.";}catch{return "Nao consegui consultar a temperatura agora. Confira a internet e tente novamente.";}
  }
  public static string FormatNews(string xml,DateTime now){
   var settings=new XmlReaderSettings{DtdProcessing=DtdProcessing.Prohibit,XmlResolver=null,MaxCharactersInDocument=2000000};var doc=new XmlDocument{XmlResolver=null};using(var reader=XmlReader.Create(new StringReader(xml),settings))doc.Load(reader);
   var items=new List<Tuple<DateTimeOffset,string,string>>();
   foreach(XmlNode item in doc.SelectNodes("/rss/channel/item")){
    var title=item.SelectSingleNode("title");var link=item.SelectSingleNode("link");var date=item.SelectSingleNode("pubDate");DateTimeOffset stamp;Uri uri;
    if(title==null||link==null||date==null||!DateTimeOffset.TryParse(date.InnerText,CultureInfo.InvariantCulture,DateTimeStyles.None,out stamp)||stamp.UtcDateTime>now.AddMinutes(10)||stamp.UtcDateTime<now.AddHours(-48)||!Uri.TryCreate(link.InnerText,UriKind.Absolute,out uri)||uri.Scheme!="https"||!(uri.Host=="bbc.com"||uri.Host.EndsWith(".bbc.com")||uri.Host=="bbc.co.uk"||uri.Host.EndsWith(".bbc.co.uk")))continue;
    string headline=Regex.Replace(WebUtility.HtmlDecode(title.InnerText),@"<[^>]+>|[\r\n]+"," ").Trim();if(headline.Length>240)headline=headline.Substring(0,240);
    items.Add(Tuple.Create(stamp,headline,uri.AbsoluteUri));
   }
   items.Sort((a,b)=>b.Item1.CompareTo(a.Item1));
   if(items.Count==0)return "A BBC News Brasil nao retornou manchetes das ultimas 48 horas. Nao vou apresentar noticias antigas como atuais.";
   var text=new StringBuilder("Manchetes recentes da BBC News Brasil, consultadas as "+now.ToLocalTime().ToString("HH:mm")+":");
   for(int i=0;i<Math.Min(3,items.Count);i++)text.Append("\n").Append(items[i].Item2).Append(" (").Append(items[i].Item1.ToLocalTime().ToString("dd/MM HH:mm")).Append(").\n").Append(items[i].Item3);
   return text.ToString();
  }
  public static async Task<string> News(CancellationToken token){
   string saved=CachedText("news");if(saved!=null)return saved;
   try{return Remember("news",FormatNews(await Get("https://feeds.bbci.co.uk/portuguese/rss.xml",token).ConfigureAwait(false),DateTime.UtcNow),120);}
   catch(OperationCanceledException){if(token.IsCancellationRequested)throw;return "A consulta das noticias demorou demais. Tente novamente.";}catch{return "Nao consegui consultar as noticias agora. Confira a internet e tente novamente.";}
  }
 }
}
