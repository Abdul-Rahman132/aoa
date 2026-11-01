require "import"
import("android.app." .. string.char(42))
import("android.os." .. string.char(42))
import("android.widget." .. string.char(42))
import("android.view." .. string.char(42))
import "android.content.Context"
import "android.content.Intent"
import "android.content.DialogInterface"
import "android.net.Uri"
import "android.media.MediaPlayer"
import "android.media.PlaybackParams"
import "android.graphics.Color"
import "android.graphics.Typeface"
import "android.graphics.drawable.ColorDrawable"
import "android.graphics.drawable.GradientDrawable"
import "android.text.TextWatcher"
import "android.content.ClipData"
import "android.app.DownloadManager"
import "android.view.inputmethod.EditorInfo"
import "android.view.inputmethod.InputMethodManager"
import "org.json.JSONObject"
import "org.json.JSONArray"
import "java.net.URL"
import "java.util.Scanner"
import "java.io.File"

local unpack = table.unpack or unpack
local unpackFn = unpack
local tafSurah = 0
local playbackSession = 0
local sleepTimerToken = 0
local sleepTimerMinutes = 0
local isPlayingTafAudio = false
local tafMpPrepared = false
local tafCurrentAudioUrl = nil

local function onUI(fn)
  pcall(function() activity.runOnUiThread(Runnable({ run = fn })) end)
end

local pref = activity.getSharedPreferences("QuranToolPrefs", Context.MODE_PRIVATE)
local reciterIdx = pref.getInt("reciterIdx", 0)
local transIdx = pref.getInt("transIdx", 0)
local vibrateEnabled = pref.getBoolean("vibrateEnabled", true)
local resumeEnabled = pref.getBoolean("resumeEnabled", false)
local repeatEnabled = pref.getBoolean("repeatEnabled", false)
local repeatCount = pref.getInt("repeatCount", 1)
local textSizeEnabled = pref.getBoolean("textSizeEnabled", false)
local textSizeVal = pref.getInt("textSizeVal", 16)
local lastSurah = pref.getInt("lastSurah", 1)
local lastAyah = pref.getInt("lastAyah", 1)
local lastPlaybackPosition = pref.getInt("lastPlaybackPosition", 0)
local lastTafSurah = pref.getInt("lastTafSurah", 0)
local lastTafPosMs = pref.getInt("lastTafPosMs", 0)
local arabicOnly = pref.getBoolean("arabicOnly", false)
local translationOnly = pref.getBoolean("translationOnly", false)
local playbackSpeed = pref.getFloat("playbackSpeed", 1.0)
local seekDuration = pref.getInt("seekDuration", 10)
local rukuMode = pref.getBoolean("rukuMode", false)
local backgroundAudio = pref.getBoolean("backgroundAudio", false)
local paraModeEnabled = pref.getBoolean("paraModeEnabled", false)
local pageModeEnabled = pref.getBoolean("pageModeEnabled", false)
local selectedPara = pref.getInt("selectedPara", 1)
local selectedPage = pref.getInt("selectedPage", 1)
local offlineCacheEnabled = pref.getBoolean("offlineCacheEnabled", true)
local bookmarksJson = pref.getString("bookmarksJson", "[]")

local function savePreferences()
  local e = pref.edit()
  e.putInt("reciterIdx", reciterIdx)
  e.putInt("transIdx", transIdx)
  e.putBoolean("vibrateEnabled", vibrateEnabled)
  e.putBoolean("resumeEnabled", resumeEnabled)
  e.putBoolean("repeatEnabled", repeatEnabled)
  e.putInt("repeatCount", repeatCount)
  e.putBoolean("textSizeEnabled", textSizeEnabled)
  e.putInt("textSizeVal", textSizeVal)
  e.putInt("lastSurah", lastSurah)
  e.putInt("lastAyah", lastAyah)
  e.putInt("lastPlaybackPosition", lastPlaybackPosition)
  e.putInt("lastTafSurah", lastTafSurah)
  e.putInt("lastTafPosMs", lastTafPosMs)
  e.putBoolean("arabicOnly", arabicOnly)
  e.putBoolean("translationOnly", translationOnly)
  e.putFloat("playbackSpeed", playbackSpeed)
  e.putInt("seekDuration", seekDuration)
  e.putBoolean("rukuMode", rukuMode)
  e.putBoolean("backgroundAudio", backgroundAudio)
  e.putBoolean("paraModeEnabled", paraModeEnabled)
  e.putBoolean("pageModeEnabled", pageModeEnabled)
  e.putInt("selectedPara", selectedPara)
  e.putInt("selectedPage", selectedPage)
  e.putBoolean("offlineCacheEnabled", offlineCacheEnabled)
  e.putString("bookmarksJson", bookmarksJson)
  e.apply()
end

local function getCacheDir()
  local dirPath = activity.getFilesDir().getAbsolutePath() .. "/quran_cache"
  local f = File(dirPath)
  if not f.exists() then pcall(function() f.mkdirs() end) end
  return dirPath
end

local function readCache(key)
  if not offlineCacheEnabled then return nil end
  local ok, content = pcall(function()
    local path = getCacheDir() .. "/" .. key:gsub("[" .. string.char(94) .. "%w" .. string.char(95) .. "%-%.]", string.char(95))
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read(string.char(42) .. "a")
    f:close()
    if data and #data > 10 then return data end
    return nil
  end)
  return ok and content or nil
end

local function writeCache(key, data)
  if not offlineCacheEnabled then return end
  if not data or #data <= 10 then return end
  pcall(function()
    local path = getCacheDir() .. "/" .. key:gsub("[" .. string.char(94) .. "%w" .. string.char(95) .. "%-%.]", string.char(95))
    local f = io.open(path, "wb")
    if f then
      f:write(data)
      f:close()
    end
  end)
end

local function clearOfflineCache()
  local count = 0
  pcall(function()
    local dir = File(getCacheDir())
    if dir.exists() then
      local files = dir.listFiles()
      if files then
        local okTbl, tbl = pcall(function() return luajava.astable(files) end)
        if okTbl and tbl then
          for idx, f in ipairs(tbl) do
            pcall(function()
              if f and f.isFile() and f.delete() then
                count = count + 1
              end
            end)
          end
        else
          for i = 0, #files - 1 do
            pcall(function()
              local f = files[i]
              if f and f.isFile() and f.delete() then
                count = count + 1
              end
            end)
          end
        end
      end
    end
  end)
  return count
end

local function copyTextToJieshuo(text, label)
  if not text or text == "" then return false end
  local success = false
  onUI(function()
    pcall(function()
      if service and type(service.copy) == "function" then
        service.copy(text) success = true
      end
    end)
    if not success then
      pcall(function()
        local cm = activity.getSystemService(Context.CLIPBOARD_SERVICE)
        pcall(function() cm.clearPrimaryClip() end)
        task(80, function()
          onUI(function()
            pcall(function()
              cm.setPrimaryClip(ClipData.newPlainText(label or "Text", text))
              success = true
            end)
          end)
        end)
      end)
    end
  end)
  return success
end

local function getBookmarks()
  local list = {}
  pcall(function()
    local arr = JSONArray(bookmarksJson or "[]")
    for i = 0, arr.length() - 1 do
      local o = arr.getJSONObject(i)
      table.insert(list, {
        surah = o.getInt("surah"),
        ayah = o.getInt("ayah"),
        note = o.optString("note", "")
      })
    end
  end)
  return list
end

local function saveBookmarks(list)
  pcall(function()
    local arr = JSONArray()
    for idx, it in ipairs(list) do
      local o = JSONObject()
      o.put("surah", it.surah)
      o.put("ayah", it.ayah)
      o.put("note", it.note or "")
      arr.put(o)
    end
    bookmarksJson = arr.toString()
    savePreferences()
  end)
end

local function addBookmark(sIdx, aIdx, noteText)
  local list = getBookmarks()
  for idx, it in ipairs(list) do
    if it.surah == sIdx and it.ayah == aIdx then
      return false
    end
  end
  table.insert(list, 1, {surah = sIdx, ayah = aIdx, note = noteText or ""})
  saveBookmarks(list)
  return true
end

local function removeBookmarkAt(index)
  local list = getBookmarks()
  if index >= 1 and index <= #list then
    table.remove(list, index)
    saveBookmarks(list)
  end
end

local function vibrate(ms)
  if not vibrateEnabled then return end
  pcall(function()
    local v = activity.getSystemService(Context.VIBRATOR_SERVICE)
    if v then v.vibrate(ms or 38) end
  end)
end

local function applySpeed(mp)
  if not mp then return end
  if not playbackSpeed or math.abs(playbackSpeed - 1.0) < 0.01 then return end
  pcall(function()
    local pp = PlaybackParams()
    pp.setSpeed(playbackSpeed)
    mp.setPlaybackParams(pp)
  end)
end

local function formatMs(ms)
  if not ms or ms < 0 then ms = 0 end
  local totalSec = math.floor(ms / 1000)
  local hrs = math.floor(totalSec / 3600)
  local mins = math.floor((totalSec % 3600) / 60)
  local secs = totalSec % 60
  if hrs > 0 then
    return string.format("%d:%02d:%02d", hrs, mins, secs)
  else
    return string.format("%02d:%02d", mins, secs)
  end
end

local function rnd(c, r)
  local gd = GradientDrawable() gd.setColor(c) gd.setCornerRadius(r or 16) return gd
end
local function grad(s, e, r)
  local gd = GradientDrawable(GradientDrawable.Orientation.TL_BR, {s, e}) gd.setCornerRadius(r or 16) return gd
end
local function brd(bg, bc, r)
  local gd = GradientDrawable() gd.setColor(bg) gd.setStroke(3, bc) gd.setCornerRadius(r or 16) return gd
end

local reciters = {
  {name="Abdul Bari Al-Thubaiti",ayahByAyah=false,folder="",server="https://server6.mp3quran.net/thubti/"},
  {name="Abdul Basit Mujawwad",ayahByAyah=true,folder="Abdul_Basit_Mujawwad_128kbps",server="https://server7.mp3quran.net/basit/Almusshaf-Al-Mujawwad/"},
  {name="Abdul Basit Murattal",ayahByAyah=true,folder="Abdul_Basit_Murattal_64kbps",server="https://server7.mp3quran.net/basit/"},
  {name="Abdul Mohsen Al-Qasim",ayahByAyah=false,folder="",server="https://server8.mp3quran.net/qasm/"},
  {name="Abdul Rahman Al-Sudais",ayahByAyah=true,folder="Abdurrahmaan_As-Sudais_192kbps",server="https://server11.mp3quran.net/sds/"},
  {name="Abdul Wadud Haneef",ayahByAyah=false,folder="",server="https://server6.mp3quran.net/wdod/"},
  {name="Abdullah Al-Juhani",ayahByAyah=false,folder="",server="https://server13.mp3quran.net/jhn/"},
  {name="Abdullah Al-Kandari",ayahByAyah=false,folder="",server="https://server6.mp3quran.net/kndr/"},
  {name="Abdullah Al-Matrood",ayahByAyah=false,folder="",server="https://server8.mp3quran.net/mtrod/"},
  {name="Abdullah Basfar",ayahByAyah=true,folder="Abdullah_Basfar_192kbps",server="https://server6.mp3quran.net/bsfr/"},
  {name="Abu Bakr Ash-Shatri",ayahByAyah=true,folder="Abu_Bakr_Ash-Shaatree_128kbps",server="https://server11.mp3quran.net/shatri/"},
  {name="Ahmad Al-Ajmi",ayahByAyah=false,folder="",server="https://server10.mp3quran.net/ajm/"},
  {name="Ahmed Al-Trabulsi",ayahByAyah=false,folder="",server="https://server10.mp3quran.net/trabulsi/"},
  {name="Akram Al-Alaqmi",ayahByAyah=false,folder="",server="https://server9.mp3quran.net/akrm/"},
  {name="Ali Al-Hudhaifi",ayahByAyah=false,folder="",server="https://server11.mp3quran.net/hthfi/"},
  {name="Ali Jaber",ayahByAyah=true,folder="Ali_Jaber_64kbps",server="https://server11.mp3quran.net/a_jbr/"},
  {name="Ayman Suwaid",ayahByAyah=false,folder="",server="https://server6.mp3quran.net/ayman/"},
  {name="Bader Al-Turki",ayahByAyah=false,folder="",server="https://server6.mp3quran.net/bader/"},
  {name="Bandar Baleela",ayahByAyah=false,folder="",server="https://server6.mp3quran.net/balilah/"},
  {name="Fares Abbad",ayahByAyah=true,folder="Fares_Abbad_64kbps",server="https://server8.mp3quran.net/frs_a/"},
  {name="Hani Ar-Rifai",ayahByAyah=true,folder="Hani_Rifai_192kbps",server="https://server8.mp3quran.net/hani/"},
  {name="Khalid Al-Qahtani",ayahByAyah=true,folder="Kahlid_Al-Qahtani_128kbps",server="https://server10.mp3quran.net/qht/"},
  {name="Khalifa Al-Tunaiji",ayahByAyah=false,folder="",server="https://server6.mp3quran.net/tunaiji/"},
  {name="Maher Al Mueaqly",ayahByAyah=true,folder="MaherAlMuaiqly128kbps",server="https://server12.mp3quran.net/maher/"},
  {name="Majed Al-Onaizi",ayahByAyah=false,folder="",server="https://server8.mp3quran.net/majd_onazi/"},
  {name="Mahmoud Khalil Al-Husary",ayahByAyah=true,folder="Husary_128kbps",server="https://server13.mp3quran.net/hssr/"},
  {name="Mahmoud Khalil Al-Husary Muallim",ayahByAyah=true,folder="Husary_Muallim_128kbps",server="https://server13.mp3quran.net/hssr/Almusshaf-Al-Mo'alium/"},
  {name="Mansour Al-Salimi",ayahByAyah=false,folder="",server="https://server8.mp3quran.net/mansor/"},
  {name="Mishary Rashid Alafasy",ayahByAyah=true,folder="Alafasy_128kbps",server="https://server8.mp3quran.net/afs/"},
  {name="Muhammad Ayyub",ayahByAyah=false,folder="",server="https://server8.mp3quran.net/ayyub/"},
  {name="Muhammad Jibreel",ayahByAyah=true,folder="Muhammad_Jibreel_128kbps",server="https://server8.mp3quran.net/jbrl/"},
  {name="Muhammad Rif'at",ayahByAyah=false,folder="",server="https://server11.mp3quran.net/mrifai/"},
  {name="Mustafa Ismail",ayahByAyah=true,folder="Mustafa_Ismail_48kbps",server="https://server8.mp3quran.net/mustafa/"},
  {name="Nasser Al Qatami",ayahByAyah=true,folder="Nasser_Alqatami_128kbps",server="https://server6.mp3quran.net/qtm/"},
  {name="Saad Al-Ghamdi",ayahByAyah=true,folder="Ghamadi_40kbps",server="https://server7.mp3quran.net/s_gmd/"},
  {name="Salah Al Budair",ayahByAyah=true,folder="Salah_Al_Budair_128kbps",server="https://server6.mp3quran.net/s_bud/"},
  {name="Saud Al-Shuraim",ayahByAyah=true,folder="Saood_ash-Shuraym_128kbps",server="https://server7.mp3quran.net/shur/"},
  {name="Sheikh Idris Abkar",ayahByAyah=false,folder="",server="https://server6.mp3quran.net/abkr/"},
  {name="Siddiq Al-Minshawy Mujawwad",ayahByAyah=true,folder="Minshawy_Mujawwad_192kbps",server="https://server10.mp3quran.net/minsh/Almusshaf-Al-Mujawwad/"},
  {name="Siddiq Al-Minshawy Murattal",ayahByAyah=true,folder="Minshawy_Murattal_128kbps",server="https://server10.mp3quran.net/minsh/"},
  {name="Yasser Al-Dosari",ayahByAyah=true,folder="Yasser_Ad-Dussary_128kbps",server="https://server11.mp3quran.net/yasser/"}
}

local translators = {
  {name="Chinese: Chinese Audio",type="cdn",id="zh.chinese"},
  {name="English: Ibrahim Walk (Test)",type="everyayah",url="https://www.everyayah.com/data/English/Ibrahim_Walk_192kbps_TEST/"},
  {name="English: Sahih Intnl & Ibrahim Walk",type="everyayah",url="https://www.everyayah.com/data/English/Sahih_Intnl_Ibrahim_Walk_192kbps/"},
  {name="French: Leclerc",type="cdn",id="fr.leclerc"},
  {name="Russian: Kuliev",type="cdn",id="ru.kuliev-audio"},
  {name="Urdu: Farhat Hashmi",type="everyayah",url="https://www.everyayah.com/data/translations/urdu_farhat_hashmi/"},
  {name="Urdu: Shamshad Ali Khan",type="everyayah",url="https://www.everyayah.com/data/translations/urdu_shamshad_ali_khan_46kbps/"}
}

local textEditions = {"zh.jian","en.sahih","en.sahih","fr.hamidullah","ru.kuliev","ur.jalandhry","ur.jalandhry"}

local surahNames = {
  "Al-Fatihah","Al-Baqarah","Ali 'Imran","An-Nisa","Al-Ma'idah","Al-An'am","Al-A'raf","Al-Anfal","At-Tawbah","Yunus",
  "Hud","Yusuf","Ar-Ra'd","Ibrahim","Al-Hijr","An-Nahl","Al-Isra","Al-Kahf","Maryam","Ta-Ha",
  "Al-Anbiya","Al-Hajj","Al-Mu'minun","An-Nur","Al-Furqan","Ash-Shu'ara","An-Naml","Al-Qasas","Al-'Ankabut","Ar-Rum",
  "Luqman","As-Sajdah","Al-Ahzab","Saba","Fatir","Ya-Sin","As-Saffat","Sad","Az-Zumar","Ghafir",
  "Fussilat","Ash-Shura","Az-Zukhruf","Ad-Dukhan","Al-Jathiyah","Al-Ahqaf","Muhammad","Al-Fath","Al-Hujurat","Qaf",
  "Adh-Dhariyat","At-Tur","An-Najm","Al-Qamar","Ar-Rahman","Al-Waqi'ah","Al-Hadid","Al-Mujadila","Al-Hashr","Al-Mumtahanah",
  "As-Saff","Al-Jumu'ah","Al-Munafiqun","At-Taghabun","At-Talaq","At-Tahrim","Al-Mulk","Al-Qalam","Al-Haqqah","Al-Ma'arij",
  "Nuh","Al-Jinn","Al-Muzzammil","Al-Muddaththir","Al-Qiyamah","Al-Insan","Al-Mursalat","An-Naba","An-Nazi'at","'Abasa",
  "At-Takwir","Al-Infitar","Al-Mutaffifin","Al-Inshiqaq","Al-Buruj","At-Tariq","Al-A'la","Al-Ghashiyah","Al-Fajr","Al-Balad",
  "Ash-Shams","Al-Layl","Ad-Duha","Ash-Sharh","At-Tin","Al-'Alaq","Al-Qadr","Al-Bayyinah","Az-Zalzalah","Al-'Adiyat",
  "Al-Qari'ah","At-Takathur","Al-'Asr","Al-Humazah","Al-Fil","Quraysh","Al-Ma'un","Al-Kawthar","Al-Kafirun","An-Nasr",
  "Al-Masad","Al-Ikhlas","Al-Falaq","An-Nas"
}

local sSPage = {1,2,50,77,106,128,151,177,187,208,221,235,249,255,262,267,277,293,305,312,322,332,342,350,359,367,377,385,396,404,411,415,418,428,434,440,446,453,458,467,477,483,489,496,499,502,507,511,515,518,520,523,526,528,531,534,537,542,545,549,551,553,554,556,558,560,562,564,566,568,570,572,574,575,577,578,580,582,583,585,586,587,587,589,590,591,591,592,593,594,595,595,596,596,597,597,598,598,599,599,600,600,601,601,601,602,602,602,603,603,603,604,604,604}
local sEPage = {1,49,76,105,127,150,176,186,207,220,234,248,254,261,266,276,292,304,311,321,331,341,349,358,366,376,384,395,403,410,414,417,427,433,439,445,452,457,466,476,482,488,495,498,501,506,510,514,517,519,522,525,527,530,533,536,541,544,548,550,552,554,555,557,559,561,563,565,567,569,571,573,575,577,578,580,581,583,584,585,586,587,589,589,590,591,592,592,593,594,595,596,596,596,597,598,598,599,599,600,600,601,601,601,602,602,602,602,603,603,603,604,604,604}

local surahCounts = {7,286,200,176,120,165,206,75,129,109,123,111,43,52,99,128,111,110,98,135,112,78,118,64,77,227,93,88,69,60,34,30,73,54,45,83,182,88,75,85,54,53,89,59,37,35,38,29,18,45,60,49,62,55,78,96,29,22,24,13,14,11,11,18,12,12,30,52,52,44,28,28,20,56,40,31,50,40,46,42,29,19,36,25,22,17,19,26,30,20,15,21,11,8,8,19,5,8,8,11,11,8,3,9,5,4,7,3,6,3,5,4,5,6}
local surahRuku = {1,40,20,24,16,20,24,10,16,11,10,12,6,7,6,16,12,12,8,8,7,10,11,9,6,11,9,9,7,6,4,5,9,6,5,6,10,5,8,9,5,5,7,6,5,5,5,4,4,5,6,4,5,4,3,4,4,4,4,3,3,3,3,4,4,4,4,4,4,3,3,3,3,4,4,3,3,3,3,4,3,3,3,3,3,3,3,3,4,3,3,3,2,2,2,3,2,2,2,3,3,2,2,2,2,2,2,2,2,2,2,2,2,2}
local surahTypes = {"M","Md","Md","Md","Md","M","M","Md","Md","M","M","M","Md","M","M","M","M","M","M","M","M","Md","M","Md","M","M","M","M","M","M","M","M","Md","M","M","M","M","M","M","M","M","M","M","M","M","M","Md","Md","Md","M","M","M","M","M","Md","M","Md","Md","Md","Md","Md","Md","Md","Md","Md","Md","M","M","M","M","M","M","M","M","M","Md","M","M","M","M","M","M","M","M","M","M","M","M","M","M","M","M","M","M","M","M","M","Md","Md","M","M","M","M","M","M","M","M","M","M","Md","M","M","M","M"}

local paraPageStart = {1,22,42,62,82,102,122,142,162,182,202,222,242,262,282,302,322,342,362,382,402,422,442,462,482,502,522,542,562,582}
local paraPageEnd = {21,41,61,81,101,121,141,161,181,201,221,241,261,281,301,321,341,361,381,401,421,441,461,481,501,521,541,561,581,604}

local paraSurahs = {
  {{1,1,7},{2,1,141}},
  {{2,142,252}},
  {{2,253,286},{3,1,92}},
  {{3,93,200},{4,1,23}},
  {{4,24,147}},
  {{4,148,176},{5,1,81}},
  {{5,82,120},{6,1,110}},
  {{6,111,165},{7,1,87}},
  {{7,88,206},{8,1,40}},
  {{8,41,75},{9,1,92}},
  {{9,93,129},{10,1,109},{11,1,5}},
  {{11,6,123},{12,1,52}},
  {{12,53,111},{13,1,43},{14,1,52}},
  {{15,1,99},{16,1,128}},
  {{17,1,111},{18,1,74}},
  {{18,75,110},{19,1,98},{20,1,135}},
  {{21,1,112},{22,1,78}},
  {{23,1,118},{24,1,64},{25,1,20}},
  {{25,21,77},{26,1,227},{27,1,55}},
  {{27,56,93},{28,1,88},{29,1,45}},
  {{29,46,69},{30,1,60},{31,1,34},{32,1,30}},
  {{33,1,73},{34,1,54},{35,1,45},{36,1,27}},
  {{36,28,83},{37,1,182},{38,1,88},{39,1,31}},
  {{39,32,75},{40,1,85},{41,1,46}},
  {{41,47,54},{42,1,53},{43,1,89},{44,1,59},{45,1,37}},
  {{46,1,35},{47,1,38},{48,1,29},{49,1,18},{50,1,45},{51,1,30}},
  {{51,31,60},{52,1,49},{53,1,62},{54,1,55},{55,1,78},{56,1,96},{57,1,29}},
  {{58,1,22},{59,1,24},{60,1,13},{61,1,14},{62,1,11},{63,1,11},{64,1,18},{65,1,12},{66,1,12}},
  {{67,1,30},{68,1,52},{69,1,52},{70,1,44},{71,1,28},{72,1,28},{73,1,20},{74,1,56},{75,1,40},{76,1,31},{77,1,50}},
  {{78,1,40},{79,1,46},{80,1,42},{81,1,29},{82,1,19},{83,1,36},{84,1,25},{85,1,22},{86,1,17},{87,1,19},{88,1,26},{89,1,30},{90,1,20},{91,1,15},{92,1,21},{93,1,11},{94,1,8},{95,1,8},{96,1,19},{97,1,5},{98,1,8},{99,1,8},{100,1,11},{101,1,11},{102,1,8},{103,1,3},{104,1,9},{105,1,5},{106,1,4},{107,1,7},{108,1,3},{109,1,6},{110,1,3},{111,1,5},{112,1,4},{113,1,5},{114,1,6}}
}

local function pageToPara(page)
  for i = 1, 30 do
    if page >= paraPageStart[i] and page <= paraPageEnd[i] then
      return i
    end
  end
  return 1
end

local function getEffectiveRange(sIdx)
  local startAy = 1
  local endAy = surahCounts[sIdx]
  local paraNum = nil
  local pageFilter = nil
  if pageModeEnabled then
    pageFilter = selectedPage
    paraNum = pageToPara(selectedPage)
  end
  if paraModeEnabled then
    paraNum = selectedPara
    if paraSurahs[selectedPara] then
      for idx, item in ipairs(paraSurahs[selectedPara]) do
        if item[1] == sIdx then
          startAy = item[2]
          endAy = item[3]
          break
        end
      end
    end
  end
  return startAy, endAy, paraNum, pageFilter
end

local mp1 = MediaPlayer()
local mp2 = MediaPlayer()
local cS, cA = 1, 1
local playMode = "single"
local currentAyahView = nil
local currentAyahPos = -1
local currentRukuPos = -1
local currentRukuView = nil
local currentRepeatTracker = 1
local surahRepeatTracker = 1
local rukuEndAyah = 0
local customRangeStart = 0
local customRangeEnd = 0
local customRangeRepeats = 1
local singlePlaying = false

local function showMainList() end
local function showSurahPopup() end

local function cleanText(s)
  if not s then return "" end
  local lt, gt, amp, quot, apos, cr, nl, caret = string.char(60), string.char(62), string.char(38), string.char(34), string.char(39), string.char(13), string.char(10), string.char(94)
  s = s:gsub(lt .. "[" .. caret .. gt .. "]+" .. gt, "")
  s = s:gsub(amp .. "quot;", quot):gsub(amp .. "amp;", amp):gsub(amp .. "lt;", lt):gsub(amp .. "gt;", gt):gsub(amp .. "#39;", apos)
  s = s:gsub(nl, " "):gsub(cr, "")
  return s
end

local function cleanTaf(s)
  if not s then return "" end
  local lt, gt, amp, quot, apos, cr, nl, tab, caret = string.char(60), string.char(62), string.char(38), string.char(34), string.char(39), string.char(13), string.char(10), string.char(9), string.char(94)
  s = s:gsub(lt .. "[" .. caret .. gt .. "]+" .. gt, "")
  s = s:gsub(amp .. "quot;", quot):gsub(amp .. "amp;", amp):gsub(amp .. "lt;", lt):gsub(amp .. "gt;", gt):gsub(amp .. "#39;", apos)
  s = s:gsub(" ", " ")
  s = s:gsub(cr, "")
  s = s:gsub("[ " .. tab .. "]+", " "):gsub(" " .. nl .. " ", nl):gsub(nl .. nl .. nl .. "+", nl .. nl)
  s = s:gsub(caret .. "%s+", ""):gsub("%s+$", "")
  return s
end

local function getGA(s,a)
  local t=0
  for i=1,s-1 do t=t+surahCounts[i] end
  return t+a
end

local function getUrl(s,a,useT)
  if useT then
    local t=translators[transIdx+1]
    if t.type == "cdn" then
      return "https://cdn.islamic.network/quran/audio/128/"..t.id.."/"..getGA(s,a)..".mp3"
    else
      return t.url..string.format("%03d%03d",s,a)..".mp3"
    end
  else
    local r=reciters[reciterIdx+1]
    if not r.ayahByAyah then return nil end
    return "https://www.everyayah.com/data/"..r.folder.."/"..string.format("%03d%03d",s,a)..".mp3"
  end
end

local function stopAudioOnly()
  playbackSession = playbackSession + 1
  singlePlaying = false
  isPlayingTafAudio = false
  tafMpPrepared = false
  pcall(function()
    mp1.setOnCompletionListener(nil)
    mp1.setOnPreparedListener(nil)
    mp1.setOnErrorListener(nil)
    mp1.stop()
    mp1.reset()
  end)
  pcall(function()
    mp2.setOnCompletionListener(nil)
    mp2.setOnPreparedListener(nil)
    mp2.setOnErrorListener(nil)
    mp2.stop()
    mp2.reset()
  end)
end

local function setHighlight(view)
  if not view then return end
  pcall(function() view.setBackground(brd(0xFF1E40AF, 0xFF7DD3FC, 14)) end)
end

local function clearHighlight()
  if currentAyahView then
    pcall(function() currentAyahView.setBackground(brd(0xFF16213E, 0xFF2563EB, 14)) end)
    currentAyahView = nil
  end
  currentAyahPos = -1
  currentRukuPos = -1
  currentRukuView = nil
end

local function stopAll()
  stopAudioOnly()
  clearHighlight()
  rukuEndAyah = 0
  customRangeStart = 0
  customRangeEnd = 0
end

local function startSleepTimer(mins)
  sleepTimerToken = sleepTimerToken + 1
  local myToken = sleepTimerToken
  sleepTimerMinutes = mins or 0
  if sleepTimerMinutes <= 0 then
    Toast.makeText(activity, "Sleep Timer turned OFF", Toast.LENGTH_SHORT).show()
    return
  end
  Toast.makeText(activity, "Sleep Timer set for " .. sleepTimerMinutes .. " minutes", Toast.LENGTH_SHORT).show()
  task(sleepTimerMinutes * 60 * 1000, function()
    if myToken == sleepTimerToken and sleepTimerMinutes > 0 then
      sleepTimerMinutes = 0
      onUI(function()
        stopAll()
        Toast.makeText(activity, "Sleep Timer finished - Playback stopped", Toast.LENGTH_LONG).show()
      end)
    end
  end)
end

local function showSleepTimerDialog()
  vibrate(35)
  local opts = {"Off (Disable Timer)", "15 Minutes", "30 Minutes", "45 Minutes", "60 Minutes"}
  local vals = {0, 15, 30, 45, 60}
  local dl = {
    LinearLayout, orientation="vertical", layout_width="fill", padding="20dp",
    background=grad(0xFF0B1220,0xFF16213E,24),
    {TextView, text="SLEEP TIMER", textSize="18sp", textColor=0xFF7DD3FC, typeface=Typeface.DEFAULT_BOLD, gravity="center"},
    {View, layout_width="fill", layout_height="6dp"},
    {TextView, text=(sleepTimerMinutes > 0 and ("Active: " .. sleepTimerMinutes .. " min") or "Currently Off"), textSize="12sp", textColor=0xFFFBBF24, gravity="center"},
    {View, layout_width="fill", layout_height="14dp"},
    {Spinner, id="spTimer", layout_width="fill", layout_height="46dp"},
    {View, layout_width="fill", layout_height="16dp"},
    {Button, id="btnSetTimer", text="APPLY TIMER", layout_width="fill", layout_height="46dp", background=grad(0xFF2563EB,0xFF1E40AF,22), textColor=0xFFFFFFFF, textSize="13sp", typeface=Typeface.DEFAULT_BOLD}
  }
  local d = AlertDialog.Builder(activity).setView(loadlayout(dl)).create()
  pcall(function() d.getWindow().setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT)) end)
  d.show()

  spTimer.setAdapter(ArrayAdapter(activity, android.R.layout.simple_spinner_dropdown_item, opts))
  for i, v in ipairs(vals) do
    if v == sleepTimerMinutes then spTimer.setSelection(i - 1) break end
  end

  btnSetTimer.onClick = function()
    vibrate(35)
    local sel = vals[spTimer.getSelectedItemPosition() + 1] or 0
    startSleepTimer(sel)
    d.dismiss()
  end
end

local function showBookmarksDialog(parentDialogToClose)
  vibrate(38)
  local bl = {
    LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", padding="18dp",
    background=grad(0xFF0B1220,0xFF16213E,28),
    {
      LinearLayout, orientation="vertical", layout_width="fill", padding="14dp",
      background=brd(0xFF1E3A5F,0xFF7DD3FC,20),
      {TextView, text="SAVED BOOKMARKS", textSize="19sp", textColor=0xFF7DD3FC, typeface=Typeface.DEFAULT_BOLD, gravity="center"},
      {View, layout_width="fill", layout_height="4dp"},
      {TextView, text="Tap OPEN SURAH to jump, or DELETE to remove", textSize="11sp", textColor=0xFF94A3B8, gravity="center"}
    },
    {View, layout_width="fill", layout_height="14dp"},
    {
      ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1", fillViewport=true,
      {LinearLayout, id="bmContainer", orientation="vertical", layout_width="fill", paddingRight="4dp"}
    },
    {View, layout_width="fill", layout_height="14dp"},
    {Button, id="btnBmClose", text="CLOSE", layout_width="fill", layout_height="46dp", background=grad(0xFF334155,0xFF1E293B,24), textColor=0xFFF1F5F9, textSize="13sp", typeface=Typeface.DEFAULT_BOLD}
  }
  local d = AlertDialog.Builder(activity).setView(loadlayout(bl)).create()
  pcall(function()
    local w = d.getWindow()
    w.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
    local dm = activity.getResources().getDisplayMetrics()
    local lp = w.getAttributes()
    lp.width = math.floor(dm.widthPixels * 0.94)
    lp.height = math.floor(dm.heightPixels * 0.85)
    w.setAttributes(lp)
  end)
  d.show()

  btnBmClose.onClick = function() vibrate(35) d.dismiss() end

  local function renderList()
    bmContainer.removeAllViews()
    local list = getBookmarks()
    if #list == 0 then
      bmContainer.addView(loadlayout({
        TextView, text="No bookmarks saved yet.\n\nOpen any Surah and tap the BOOKMARK button to save your place.",
        textSize="14sp", textColor=0xFF94A3B8, gravity="center", padding="30dp"
      }))
      return
    end
    for idx, item in ipairs(list) do
      local sName = surahNames[item.surah] or ("Surah " .. item.surah)
      local titleTxt = item.surah .. ". Surah " .. sName .. "  (Ayah " .. item.ayah .. ")"
      local subTxt = (item.note and item.note ~= "") and item.note or "Tap OPEN SURAH to jump to this Ayah"
      local row = loadlayout({
        LinearLayout, orientation="vertical", layout_width="fill", padding="14dp",
        background=brd(0xFF16213E,0xFF2563EB,16),
        {TextView, text=titleTxt, textSize="15sp", textColor=0xFFFBBF24, typeface=Typeface.DEFAULT_BOLD},
        {View, layout_width="fill", layout_height="4dp"},
        {TextView, text=subTxt, textSize="12sp", textColor=0xFFE2E8F0},
        {View, layout_width="fill", layout_height="10dp"},
        {
          LinearLayout, orientation="horizontal", layout_width="fill",
          {Button, text="OPEN SURAH", layout_width="0dp", layout_weight="1", layout_height="40dp", textSize="11sp", background=grad(0xFF2563EB,0xFF1E40AF,18), textColor=0xFFFFFFFF, typeface=Typeface.DEFAULT_BOLD,
            onClick=function()
              vibrate(35)
              lastSurah = item.surah
              lastAyah = item.ayah
              savePreferences()
              d.dismiss()
              if parentDialogToClose then pcall(function() parentDialogToClose.dismiss() end) end
              task(200, function() showSurahPopup(item.surah, nil, item.ayah) end)
            end},
          {View, layout_width="8dp", layout_height="fill"},
          {Button, text="DELETE", layout_width="90dp", layout_height="40dp", textSize="11sp", background=grad(0xFFDC2626,0xFF991B1B,18), textColor=0xFFFFFFFF, typeface=Typeface.DEFAULT_BOLD,
            onClick=function()
              vibrate(35)
              removeBookmarkAt(idx)
              Toast.makeText(activity, "Bookmark removed", Toast.LENGTH_SHORT).show()
              renderList()
            end}
        }
      })
      bmContainer.addView(row)
      bmContainer.addView(loadlayout({View, layout_width="fill", layout_height="8dp"}))
    end
  end
  renderList()
end

-- ===================================================
-- SETTINGS (Smooth Swiping & Responsive Height)
-- ===================================================
local function showSettings()
  vibrate(38)
  local fs = {"Standard (14sp)","Medium (18sp)","Large (22sp)","Extra Large (26sp)"}
  local fv = {14,18,22,26}
  local ini = 0
  for i,v in ipairs(fv) do if v == textSizeVal then ini=i-1 break end end

  local speedLabels = {"0.5x","0.75x","1.0x (Normal)","1.25x","1.5x","2.0x"}
  local speedValues = {0.5, 0.75, 1.0, 1.25, 1.5, 2.0}
  local sIdx2 = 2
  for i,v in ipairs(speedValues) do if math.abs(v - playbackSpeed) < 0.01 then sIdx2=i-1 break end end

  local seekLabels = {"5 Seconds","10 Seconds","15 Seconds","20 Seconds","25 Seconds","30 Seconds","35 Seconds","40 Seconds","45 Seconds","50 Seconds","55 Seconds","60 Seconds"}
  local seekValues = {5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60}
  local seekSelIdx = 1
  for i,v in ipairs(seekValues) do if v == seekDuration then seekSelIdx = i-1 break end end

  local paraLabels = {}
  for i = 1, 30 do table.insert(paraLabels, "Para "..i) end

  local function buildPageLabels(filterByPara, pIdx)
    local lbls = {}
    local sp = 1
    local ep = 604
    if filterByPara then
      sp = paraPageStart[pIdx] or 1
      ep = paraPageEnd[pIdx] or 21
    end
    for p = sp, ep do table.insert(lbls, "Page "..p.." (Para "..pageToPara(p)..")") end
    return lbls, sp
  end

  local function toggleCard(heading, cbId, cbLabel, sub, checked)
    return {
      LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
      background=brd(0xFF16213E,0xFF2563EB,16),
      {TextView,text=heading,textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
      {View,layout_width="fill",layout_height="8dp"},
      {CheckBox,id=cbId,text=cbLabel,textColor=0xFFF1F5F9,textSize="15sp",checked=checked},
      {View,layout_width="fill",layout_height="4dp"},
      {TextView,text=sub,textSize="11sp",textColor=0xFF94A3B8,paddingLeft="32dp"}
    }
  end

  local sl = {
    LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", padding="18dp",
    background=grad(0xFF0B1220,0xFF16213E,28),
    {
      LinearLayout, orientation="vertical", layout_width="fill", padding="14dp",
      background=brd(0xFF1E3A5F,0xFF7DD3FC,20),
      {TextView,text="SETTINGS",textSize="21sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD,gravity="center"},
      {View,layout_width="fill",layout_height="4dp"},
      {TextView,text="Personalize your Quran experience",textSize="11sp",textColor=0xFF94A3B8,gravity="center"}
    },
    {View,layout_width="fill",layout_height="12dp"},
    {
      ScrollView, id="settingsScroll", layout_width="fill", layout_height="0dp", layout_weight="1", fillViewport=true,
      {
        LinearLayout, orientation="vertical", layout_width="fill", paddingRight="4dp",
        -- 1. Playback Speed
        {
          LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
          background=brd(0xFF16213E,0xFF2563EB,16),
          {TextView,text="Playback Speed",textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="8dp"},
          {TextView,text="Speed up or slow down recitation and audio Tafseer",textSize="11sp",textColor=0xFF94A3B8},
          {View,layout_width="fill",layout_height="8dp"},
          {Spinner,id="spinSpeed",layout_width="fill",layout_height="46dp"}
        },
        {View,layout_width="fill",layout_height="10dp"},
        -- 2. Forward / Rewind Duration
        {
          LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
          background=brd(0xFF16213E,0xFF2563EB,16),
          {TextView,text="Forward / Rewind Duration",textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="8dp"},
          {TextView,text="Select jump interval for forward and rewind buttons (5s to 60s)",textSize="11sp",textColor=0xFF94A3B8},
          {View,layout_width="fill",layout_height="8dp"},
          {Spinner,id="spinSeek",layout_width="fill",layout_height="46dp"}
        },
        {View,layout_width="fill",layout_height="10dp"},
        -- 3. Arabic Only Mode
        toggleCard("Arabic Only Mode","cbArabicOnly","Play Arabic Only","Skip translation, play only the Arabic ayah",arabicOnly),
        {View,layout_width="fill",layout_height="10dp"},
        -- 4. Translation Only Mode
        toggleCard("Translation Only Mode","cbTranslationOnly","Play Translation Only","Skip Arabic, play only the translation ayah",translationOnly),
        {View,layout_width="fill",layout_height="10dp"},
        -- 5. Ruku Mode
        toggleCard("Ruku Mode","cbRukuMode","Enable Ruku Mode","Browse and play Surahs by Ruku instead of individual Ayahs",rukuMode),
        {View,layout_width="fill",layout_height="10dp"},
        -- 6. Para Mode
        {
          LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
          background=brd(0xFF16213E,0xFF2563EB,16),
          {TextView,text="Para Mode",textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="8dp"},
          {CheckBox,id="cbParaMode",text="Enable Para Mode",textColor=0xFFF1F5F9,textSize="15sp",checked=paraModeEnabled},
          {View,layout_width="fill",layout_height="4dp"},
          {TextView,text="Filter Surahs and Ayahs by a specific Para (Juz 1-30)",textSize="11sp",textColor=0xFF94A3B8,paddingLeft="32dp"},
          {View,layout_width="fill",layout_height="8dp"},
          {
            LinearLayout,id="layoutParaSelect",orientation="vertical",layout_width="fill",paddingLeft="32dp",
            visibility=(paraModeEnabled and View.VISIBLE or View.GONE),
            {TextView,text="Select Para",textColor=0xFF7DD3FC,textSize="13sp",typeface=Typeface.DEFAULT_BOLD},
            {View,layout_width="fill",layout_height="6dp"},
            {Spinner,id="spinPara",layout_width="fill",layout_height="44dp"}
          }
        },
        {View,layout_width="fill",layout_height="10dp"},
        -- 7. Page Mode
        {
          LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
          background=brd(0xFF16213E,0xFF2563EB,16),
          {TextView,text="Page Mode (1 - 604)",textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="8dp"},
          {CheckBox,id="cbPageMode",text="Enable Page Mode",textColor=0xFFF1F5F9,textSize="15sp",checked=pageModeEnabled},
          {View,layout_width="fill",layout_height="4dp"},
          {TextView,text="Filter Surahs and Ayahs to an exact Quran page (1-604)",textSize="11sp",textColor=0xFF94A3B8,paddingLeft="32dp"},
          {View,layout_width="fill",layout_height="8dp"},
          {
            LinearLayout,id="layoutPageSelect",orientation="vertical",layout_width="fill",paddingLeft="32dp",
            visibility=(pageModeEnabled and View.VISIBLE or View.GONE),
            {TextView,text="Select Page",textColor=0xFF7DD3FC,textSize="13sp",typeface=Typeface.DEFAULT_BOLD},
            {View,layout_width="fill",layout_height="6dp"},
            {Spinner,id="spinPage",layout_width="fill",layout_height="44dp"}
          }
        },
        {View,layout_width="fill",layout_height="10dp"},
        -- 8. Resume Playback
        toggleCard("Resume Playback","cbResume","Enable Resume","Continue recitation and audio Tafseer from where you left off",resumeEnabled),
        {View,layout_width="fill",layout_height="10dp"},
        -- 9. Background Audio
        toggleCard("Background Audio","cbBgAudio","Enable Background Playback","Keep playing audio when the app is minimized or screen is off",backgroundAudio),
        {View,layout_width="fill",layout_height="10dp"},
        -- 10. Offline Cache (Clean & Professional)
        {
          LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
          background=brd(0xFF16213E,0xFF2563EB,16),
          {TextView,text="Offline Cache",textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="8dp"},
          {CheckBox,id="cbOfflineCache",text="Enable Offline Cache",textColor=0xFFF1F5F9,textSize="15sp",checked=offlineCacheEnabled},
          {View,layout_width="fill",layout_height="4dp"},
          {TextView,text="Save opened Surahs, Translations & Tafseer for offline access",textSize="11sp",textColor=0xFF94A3B8,paddingLeft="32dp"},
          {View,layout_width="fill",layout_height="10dp"},
          {Button,id="btnClearCache",text="CLEAR OFFLINE CACHE",layout_width="fill",layout_height="40dp",background=grad(0xFF334155,0xFF1E293B,18),textColor=0xFFF1F5F9,textSize="11sp",typeface=Typeface.DEFAULT_BOLD}
        },
        {View,layout_width="fill",layout_height="10dp"},
        -- 11. Repeat Full Surah
        {
          LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
          background=brd(0xFF16213E,0xFF2563EB,16),
          {TextView,text="Repeat Full Surah",textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="8dp"},
          {CheckBox,id="cbRepeat",text="Enable Repeat",textColor=0xFFF1F5F9,textSize="15sp",checked=repeatEnabled},
          {View,layout_width="fill",layout_height="4dp"},
          {TextView,text="Loop the Surah a chosen number of times",textSize="11sp",textColor=0xFF94A3B8,paddingLeft="32dp"},
          {View,layout_width="fill",layout_height="8dp"},
          {
            LinearLayout,id="layoutRepeatCount",orientation="horizontal",layout_width="fill",gravity="center_vertical",paddingLeft="32dp",
            visibility=(repeatEnabled and View.VISIBLE or View.GONE),
            {TextView,text="Repeat Count: ",textColor=0xFF7DD3FC,textSize="13sp"},
            {EditText,id="etRepeatCount",text=tostring(repeatCount),inputType=2,layout_width="90dp",layout_height="42dp",textColor=0xFFF1F5F9,textSize="14sp",gravity="center",background=brd(0xFF0B1220,0xFF3B82F6,12)}
          }
        },
        {View,layout_width="fill",layout_height="10dp"},
        -- 12. Adjust Font Size
        {
          LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
          background=brd(0xFF16213E,0xFF2563EB,16),
          {TextView,text="Adjust Font Size",textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="8dp"},
          {CheckBox,id="cbTextSize",text="Enable Font Size Setting",textColor=0xFFF1F5F9,textSize="15sp",checked=textSizeEnabled},
          {View,layout_width="fill",layout_height="4dp"},
          {TextView,text="Choose from 4 text size presets (14sp to 26sp)",textSize="11sp",textColor=0xFF94A3B8,paddingLeft="32dp"},
          {View,layout_width="fill",layout_height="8dp"},
          {
            LinearLayout,id="layoutTextSize",orientation="horizontal",layout_width="fill",gravity="center_vertical",paddingLeft="32dp",
            visibility=(textSizeEnabled and View.VISIBLE or View.GONE),
            {TextView,text="Size: ",textColor=0xFF7DD3FC,textSize="13sp"},
            {Spinner,id="spinTextSize",layout_width="0dp",layout_weight="1",layout_height="42dp"}
          }
        },
        {View,layout_width="fill",layout_height="10dp"},
        -- 13. Haptic Vibration
        toggleCard("Haptic Vibration","cbVib","Enable Vibration","Gentle feedback on button taps",vibrateEnabled),
        {View,layout_width="fill",layout_height="10dp"},
        -- 14. Sleep Timer
        {
          LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
          background=brd(0xFF16213E,0xFF2563EB,16),
          {TextView,text="Sleep Timer",textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="8dp"},
          {Button,id="btnOpenTimer",text="SET SLEEP TIMER",layout_width="fill",layout_height="42dp",background=grad(0xFF0EA5E9,0xFF0369A1,18),textColor=0xFFFFFFFF,textSize="12sp",typeface=Typeface.DEFAULT_BOLD}
        },
        {View,layout_width="fill",layout_height="10dp"}
      }
    },
    {View,layout_width="fill",layout_height="14dp"},
    {Button,id="btnSave",text="SAVE",layout_width="fill",layout_height="50dp",background=grad(0xFF2563EB,0xFF1E40AF,24),textColor=0xFFFFFFFF,textSize="14sp",typeface=Typeface.DEFAULT_BOLD}
  }
  local d = AlertDialog.Builder(activity).setView(loadlayout(sl)).create()
  pcall(function()
    local w = d.getWindow()
    w.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
    local dm = activity.getResources().getDisplayMetrics()
    local lp = w.getAttributes()
    lp.width = math.floor(dm.widthPixels * 0.94)
    lp.height = math.floor(dm.heightPixels * 0.88)
    w.setAttributes(lp)
  end)
  d.show()

  cbRepeat.setOnCheckedChangeListener({onCheckedChanged=function(v,c) vibrate(30) layoutRepeatCount.setVisibility(c and View.VISIBLE or View.GONE) end})
  cbTextSize.setOnCheckedChangeListener({onCheckedChanged=function(v,c) vibrate(30) layoutTextSize.setVisibility(c and View.VISIBLE or View.GONE) end})
  spinTextSize.setAdapter(ArrayAdapter(activity,android.R.layout.simple_spinner_dropdown_item,fs))
  spinTextSize.setSelection(ini)
  spinSpeed.setAdapter(ArrayAdapter(activity,android.R.layout.simple_spinner_dropdown_item,speedLabels))
  spinSpeed.setSelection(sIdx2)
  spinSeek.setAdapter(ArrayAdapter(activity,android.R.layout.simple_spinner_dropdown_item,seekLabels))
  spinSeek.setSelection(seekSelIdx)

  spinPara.setAdapter(ArrayAdapter(activity,android.R.layout.simple_spinner_dropdown_item,paraLabels))
  spinPara.setSelection((selectedPara or 1) - 1)

  local currentPageStartOffset = 1
  local function refreshPageSpinner()
    local filterByPara = cbParaMode.isChecked()
    local pIdx = spinPara.getSelectedItemPosition() + 1
    local newLabels, newStart = buildPageLabels(filterByPara, pIdx)
    currentPageStartOffset = newStart
    spinPage.setAdapter(ArrayAdapter(activity,android.R.layout.simple_spinner_dropdown_item,newLabels))
    local currentPage = selectedPage or 1
    local idx = currentPage - newStart
    if idx < 0 or idx >= #newLabels then idx = 0 end
    spinPage.setSelection(idx)
  end

  refreshPageSpinner()

  spinPara.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
    onItemSelected=function(p,v,pos,id)
      if cbParaMode.isChecked() then refreshPageSpinner() end
    end,
    onNothingSelected=function(p) end
  })

  cbParaMode.setOnCheckedChangeListener({onCheckedChanged=function(v,c)
    vibrate(30)
    layoutParaSelect.setVisibility(c and View.VISIBLE or View.GONE)
    refreshPageSpinner()
  end})
  cbPageMode.setOnCheckedChangeListener({onCheckedChanged=function(v,c)
    vibrate(30)
    layoutPageSelect.setVisibility(c and View.VISIBLE or View.GONE)
    refreshPageSpinner()
  end})

  cbArabicOnly.setOnCheckedChangeListener({onCheckedChanged=function(v,c)
    if c then vibrate(30) cbTranslationOnly.setChecked(false) end
  end})
  cbTranslationOnly.setOnCheckedChangeListener({onCheckedChanged=function(v,c)
    if c then vibrate(30) cbArabicOnly.setChecked(false) end
  end})

  btnOpenTimer.onClick = function() showSleepTimerDialog() end
  btnClearCache.onClick = function()
    vibrate(35)
    local removed = clearOfflineCache()
    Toast.makeText(activity, "Offline cache cleared (" .. removed .. " files removed)", Toast.LENGTH_SHORT).show()
  end

  btnSave.setOnClickListener(View.OnClickListener{onClick=function()
    vibrate(35)
    resumeEnabled = cbResume.isChecked()
    backgroundAudio = cbBgAudio.isChecked()
    offlineCacheEnabled = cbOfflineCache.isChecked()
    repeatEnabled = cbRepeat.isChecked()
    local pc = tonumber(etRepeatCount.getText().toString())
    repeatCount = (pc and pc > 0) and pc or 1
    textSizeEnabled = cbTextSize.isChecked()
    textSizeVal = fv[spinTextSize.getSelectedItemPosition()+1] or 16
    vibrateEnabled = cbVib.isChecked()
    arabicOnly = cbArabicOnly.isChecked()
    translationOnly = cbTranslationOnly.isChecked()
    playbackSpeed = speedValues[spinSpeed.getSelectedItemPosition()+1] or 1.0
    seekDuration = seekValues[spinSeek.getSelectedItemPosition()+1] or 10
    rukuMode = cbRukuMode.isChecked()
    paraModeEnabled = cbParaMode.isChecked()
    pageModeEnabled = cbPageMode.isChecked()
    selectedPara = spinPara.getSelectedItemPosition() + 1
    selectedPage = currentPageStartOffset + spinPage.getSelectedItemPosition()
    savePreferences()
    Toast.makeText(activity,"Settings saved",Toast.LENGTH_SHORT).show()
    d.dismiss()
    task(200, function() pcall(function() showMainList() end) end)
  end})
end

local function showReader(sIdx)
  vibrate(38)
  stopAll()
  local ed = textEditions[transIdx+1] or "ur.jalandhry"
  local afs = (textSizeEnabled and textSizeVal or 14).."sp"
  local aafs = (textSizeEnabled and (textSizeVal+2) or 16).."sp"

  local rl = {
    LinearLayout,orientation="vertical",layout_width="fill",layout_height="fill",padding="18dp",
    background=grad(0xFF0B1220,0xFF16213E,28),
    {
      LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
      background=brd(0xFF1E3A5F,0xFF7DD3FC,20),
      {TextView,text="Surah "..surahNames[sIdx],textSize="20sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD,gravity="center"},
      {View,layout_width="fill",layout_height="4dp"},
      {TextView,text="READ AND COPY TEXT",textSize="10sp",textColor=0xFF94A3B8,gravity="center"}
    },
    {View,layout_width="fill",layout_height="14dp"},
    {
      ScrollView, id="rdScroll", layout_width="fill", layout_height="0dp", layout_weight="1", fillViewport=true,
      {LinearLayout, id="rdCards", orientation="vertical", layout_width="fill", paddingRight="4dp"}
    },
    {View,layout_width="fill",layout_height="14dp"},
    {Button,id="btnRdClose",text="CLOSE READER",layout_width="fill",layout_height="48dp",background=grad(0xFF334155,0xFF1E293B,24),textColor=0xFFF1F5F9,textSize="13sp",typeface=Typeface.DEFAULT_BOLD}
  }
  local d = AlertDialog.Builder(activity).setView(loadlayout(rl)).create()
  pcall(function()
    local w = d.getWindow()
    w.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
    local dm = activity.getResources().getDisplayMetrics()
    local lp = w.getAttributes()
    lp.width = math.floor(dm.widthPixels * 0.94)
    lp.height = math.floor(dm.heightPixels * 0.88)
    w.setAttributes(lp)
  end)
  d.show()
  btnRdClose.onClick=function() vibrate(35) d.dismiss() end
  rdCards.addView(loadlayout({TextView,text="Loading...",textSize=afs,textColor=0xFF7DD3FC,gravity="center",padding="25dp"}))

  local arCacheKey = "surah_ar" .. string.char(95) .. sIdx .. ".json"
  local trCacheKey = "surah_tr" .. string.char(95) .. sIdx .. string.char(95) .. ed .. ".json"
  local cachedAr = readCache(arCacheKey)
  local cachedTr = readCache(trCacheKey)

  task(function(s, ed, cAr, cTr)
    local function f(u)
      local ok,res = pcall(function()
        local url=URL(u)
        local c=url.openConnection()
        c.setRequestMethod("GET")
        c.setRequestProperty("User-Agent","Mozilla/5.0")
        c.setConnectTimeout(8000)
        c.setReadTimeout(8000)
        if c.getResponseCode() == 200 then
          local sc=Scanner(c.getInputStream(),"UTF-8")
          sc.useDelimiter(string.char(92) .. "A")
          local t=sc.hasNext() and sc.next() or ""
          sc.close()
          return t
        end
        return nil
      end)
      return ok and res or nil
    end
    local arData = cAr or f("https://api.alquran.cloud/v1/surah/"..s)
    local trData = cTr or f("https://api.alquran.cloud/v1/surah/"..s.."/"..ed)
    return arData, trData
  end, sIdx, ed, cachedAr, cachedTr, function(arJ,trJ)
    rdCards.removeAllViews()
    if not arJ then
      rdCards.addView(loadlayout({TextView,text="Network issue. Please check internet connection.",textSize=afs,textColor=0xFFEF4444,gravity="center",padding="20dp"}))
      return
    end
    if not cachedAr then writeCache(arCacheKey, arJ) end
    if trJ and not cachedTr then writeCache(trCacheKey, trJ) end

    local ayAr,ayTr={},{}
    pcall(function()
      local o=JSONObject(arJ)
      local d=o.getJSONObject("data")
      local a=d.getJSONArray("ayahs")
      for i=0,a.length()-1 do
        local x=a.getJSONObject(i)
        table.insert(ayAr,cleanText(x.getString("text")))
      end
    end)
    if trJ then
      pcall(function()
        local o=JSONObject(trJ)
        local d=o.getJSONObject("data")
        local a=d.getJSONArray("ayahs")
        for i=0,a.length()-1 do
          local x=a.getJSONObject(i)
          table.insert(ayTr,cleanText(x.getString("text")))
        end
      end)
    end
    local fa,ft={},{}
    for i,t in ipairs(ayAr) do table.insert(fa,"["..i.."] "..t) end
    for i,t in ipairs(ayTr) do table.insert(ft,"["..i.."] "..t) end
    local fullAr = table.concat(fa, string.char(10) .. string.char(10))
    local fullTr = table.concat(ft, string.char(10) .. string.char(10))

    rdCards.addView(loadlayout({
      LinearLayout,orientation="vertical",layout_width="fill",
      background=brd(0xFF16213E,0xFF2563EB,18),padding="18dp",
      {TextView,text="ARABIC TEXT",textSize="13sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
      {View,layout_width="fill",layout_height="12dp"},
      {TextView,text=fullAr,textSize=aafs,textColor=0xFFF1F5F9,gravity="right",typeface=Typeface.DEFAULT_BOLD},
      {View,layout_width="fill",layout_height="16dp"},
      {Button,text="COPY ARABIC TEXT",layout_width="fill",layout_height="46dp",textSize="12sp",background=grad(0xFF0EA5E9,0xFF0369A1,22),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD,
        onClick=function()
          vibrate(35)
          copyTextToJieshuo(fullAr, "ArabicText")
          Toast.makeText(activity,"Arabic text copied!",Toast.LENGTH_SHORT).show()
        end}
    }))
    rdCards.addView(loadlayout({View,layout_width="fill",layout_height="14dp"}))
    rdCards.addView(loadlayout({
      LinearLayout,orientation="vertical",layout_width="fill",
      background=brd(0xFF16213E,0xFF7C3AED,18),padding="18dp",
      {TextView,text="TRANSLATION",textSize="13sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
      {View,layout_width="fill",layout_height="6dp"},
      {TextView,text=translators[transIdx+1].name,textSize="11sp",textColor=0xFF94A3B8},
      {View,layout_width="fill",layout_height="12dp"},
      {TextView,text=fullTr,textSize=afs,textColor=0xFFE2E8F0},
      {View,layout_width="fill",layout_height="16dp"},
      {Button,text="COPY TRANSLATION",layout_width="fill",layout_height="46dp",textSize="12sp",background=grad(0xFF7C3AED,0xFF5B21B6,22),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD,
        onClick=function()
          vibrate(35)
          copyTextToJieshuo(fullTr, "Translation")
          Toast.makeText(activity,"Translation copied!",Toast.LENGTH_SHORT).show()
        end}
    }))
  end)
end

local function parseArchiveSurahUrl(metaJson, archiveId, sIdx)
  if not metaJson or metaJson == "" then return nil end
  local targetPrefix = string.format("%03d", sIdx)
  local foundMp3 = nil
  local foundOgg = nil
  pcall(function()
    local o = JSONObject(metaJson)
    local files = o.getJSONArray("files")
    for i = 0, files.length() - 1 do
      local fObj = files.getJSONObject(i)
      local name = fObj.optString("name", "")
      local numMatch = name:gsub(string.char(94) .. "%s+", ""):match(string.char(94) .. "(%d%d%d)")
      if numMatch == targetPrefix then
        local lowerName = name:lower()
        if lowerName:sub(-4) == ".mp3" and not foundMp3 then
          foundMp3 = "https://archive.org/download/" .. archiveId .. "/" .. Uri.encode(name, "/")
        elseif lowerName:sub(-4) == ".ogg" and not foundOgg then
          foundOgg = "https://archive.org/download/" .. archiveId .. "/" .. Uri.encode(name, "/")
        end
      end
    end
  end)
  return foundMp3 or foundOgg
end

local function showTafseer(sIdx)
  vibrate(38)
  stopAll()
  local afs = (textSizeEnabled and textSizeVal or 14).."sp"
  local aafs = (textSizeEnabled and (textSizeVal+2) or 16).."sp"
  local fullTextForCopy = ""
  tafSurah = sIdx
  isPlayingTafAudio = false
  tafMpPrepared = false
  tafCurrentAudioUrl = nil

  local pendingSeekMs = 0
  if resumeEnabled and lastTafSurah == sIdx and lastTafPosMs > 0 then
    pendingSeekMs = lastTafPosMs
  end

  local dialogOpen = true
  local metaCacheKey = "archive_meta_tafseer_ibnkathir_hq.json"

  local tl = {
    LinearLayout,orientation="vertical",layout_width="fill",layout_height="fill",padding="16dp",
    background=grad(0xFF0B1220,0xFF16213E,28),
    {
      LinearLayout,orientation="vertical",layout_width="fill",padding="14dp",
      background=brd(0xFF1E3A5F,0xFF7DD3FC,20),
      {TextView,text="TAFSEER IBN KATHIR",textSize="19sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD,gravity="center"},
      {View,layout_width="fill",layout_height="4dp"},
      {TextView,text="Surah "..surahNames[sIdx].."  -  Authentic Audio and Written Commentary",textSize="12sp",textColor=0xFFFBBF24,typeface=Typeface.DEFAULT_BOLD,gravity="center"}
    },
    {View,layout_width="fill",layout_height="12dp"},
    {
      LinearLayout,orientation="horizontal",layout_width="fill",gravity="center",
      {Button,id="btnRw",text="-"..seekDuration.."s",layout_width="80dp",layout_height="48dp",textSize="13sp",background=grad(0xFF0EA5E9,0xFF0369A1,22),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD},
      {View,layout_width="8dp",layout_height="fill"},
      {Button,id="btnPlay",text="PLAY AUDIO",layout_width="0dp",layout_weight="1",layout_height="48dp",textSize="13sp",background=grad(0xFF2563EB,0xFF1E40AF,24),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD},
      {View,layout_width="8dp",layout_height="fill"},
      {Button,id="btnFw",text="+"..seekDuration.."s",layout_width="80dp",layout_height="48dp",textSize="13sp",background=grad(0xFF0EA5E9,0xFF0369A1,22),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD}
    },
    {View,layout_width="fill",layout_height="10dp"},
    {SeekBar,id="seek",layout_width="fill",layout_height="36dp",progress=0,max=100},
    {View,layout_width="fill",layout_height="4dp"},
    {TextView,id="tvSt",text="Loading Tafseer audio...",textSize="11sp",textColor=0xFF7DD3FC,gravity="center"},
    {View,layout_width="fill",layout_height="10dp"},
    {
      ScrollView, id="tafScr", layout_width="fill", layout_height="0dp", layout_weight="1", fillViewport=true,
      {LinearLayout, id="tafCon", orientation="vertical", layout_width="fill", paddingRight="4dp"}
    },
    {View,layout_width="fill",layout_height="10dp"},
    {
      LinearLayout,orientation="horizontal",layout_width="fill",
      {Button,id="btnCpy",text="COPY TAFSEER",layout_width="0dp",layout_weight="1",layout_height="44dp",textSize="11sp",background=grad(0xFF0284C7,0xFF01579B,20),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD},
      {View,layout_width="8dp",layout_height="fill"},
      {Button,id="btnDlTaf",text="DOWNLOAD MP3",layout_width="0dp",layout_weight="1",layout_height="44dp",textSize="11sp",background=grad(0xFF059669,0xFF065F46,20),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD}
    },
    {View,layout_width="fill",layout_height="8dp"},
    {Button,id="btnClose",text="CLOSE",layout_width="fill",layout_height="44dp",background=grad(0xFF334155,0xFF1E293B,24),textColor=0xFFF1F5F9,textSize="12sp",typeface=Typeface.DEFAULT_BOLD}
  }
  local d = AlertDialog.Builder(activity).setView(loadlayout(tl)).create()
  pcall(function()
    local w = d.getWindow()
    w.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
    local dm = activity.getResources().getDisplayMetrics()
    local lp = w.getAttributes()
    lp.width = math.floor(dm.widthPixels * 0.94)
    lp.height = math.floor(dm.heightPixels * 0.88)
    w.setAttributes(lp)
  end)
  d.setOnDismissListener(DialogInterface.OnDismissListener{
    onDismiss = function()
      dialogOpen = false
      pcall(function()
        if tafMpPrepared and mp1.isPlaying() then
          lastTafSurah = sIdx
          lastTafPosMs = mp1.getCurrentPosition()
          savePreferences()
        end
      end)
      if not backgroundAudio then
        stopAudioOnly()
      end
    end
  })
  d.show()

  local function scheduleProgressTick()
    if not dialogOpen then return end
    task(1000, function()
      if not dialogOpen then return end
      onUI(function()
        if isPlayingTafAudio and tafMpPrepared then
          pcall(function()
            if mp1.isPlaying() then
              local pos = mp1.getCurrentPosition()
              local dur = mp1.getDuration()
              if dur and dur > 0 then
                local pct = math.floor((pos / dur) * 100)
                if pct > 100 then pct = 100 end
                seek.setProgress(pct)
                tvSt.setText("Tafseer Audio: " .. formatMs(pos) .. " / " .. formatMs(dur) .. " (" .. pct .. "%)")
                lastTafSurah = sIdx
                lastTafPosMs = pos
              end
            end
          end)
        end
      end)
      scheduleProgressTick()
    end)
  end
  scheduleProgressTick()

  local function startTafseerAudio()
    if not tafCurrentAudioUrl then
      Toast.makeText(activity, "Tafseer audio is loading, please wait...", Toast.LENGTH_SHORT).show()
      return
    end
    stopAudioOnly()
    local mySession = playbackSession
    isPlayingTafAudio = true
    tafMpPrepared = false
    btnPlay.setText("LOADING...")
    tvSt.setText("Buffering Tafseer Ibn Kathir Audio...")

    pcall(function()
      mp1.reset()
      mp1.setDataSource(tafCurrentAudioUrl)
      mp1.setOnPreparedListener(MediaPlayer.OnPreparedListener{
        onPrepared = function(p)
          if mySession ~= playbackSession then return end
          tafMpPrepared = true
          applySpeed(p)
          if pendingSeekMs > 0 then
            pcall(function() p.seekTo(pendingSeekMs) end)
            pendingSeekMs = 0
          end
          p.start()
          onUI(function()
            btnPlay.setText("PAUSE")
            local dur = p.getDuration()
            tvSt.setText("Tafseer Ibn Kathir Audio (" .. formatMs(dur) .. ")")
          end)
        end
      })
      mp1.setOnCompletionListener(MediaPlayer.OnCompletionListener{
        onCompletion = function()
          if mySession ~= playbackSession then return end
          isPlayingTafAudio = false
          lastTafPosMs = 0
          savePreferences()
          onUI(function()
            btnPlay.setText("PLAY AUDIO")
            seek.setProgress(100)
            tvSt.setText("Tafseer Audio Completed 100%")
          end)
        end
      })
      mp1.setOnErrorListener(MediaPlayer.OnErrorListener{
        onError = function(mp, what, extra)
          if mySession ~= playbackSession then return true end
          onUI(function()
            Toast.makeText(activity, "Network error playing Tafseer audio", Toast.LENGTH_SHORT).show()
            btnPlay.setText("PLAY AUDIO")
            tvSt.setText("Error loading audio. Tap PLAY to retry.")
            isPlayingTafAudio = false
          end)
          return true
        end
      })
      mp1.prepareAsync()
    end)
  end

  btnPlay.onClick = function()
    vibrate(38)
    if tafMpPrepared then
      pcall(function()
        if mp1.isPlaying() then
          mp1.pause()
          isPlayingTafAudio = false
          lastTafSurah = sIdx
          lastTafPosMs = mp1.getCurrentPosition()
          savePreferences()
          btnPlay.setText("PLAY AUDIO")
          tvSt.setText("Paused: " .. formatMs(mp1.getCurrentPosition()))
        else
          mp1.start()
          isPlayingTafAudio = true
          btnPlay.setText("PAUSE")
        end
      end)
    else
      startTafseerAudio()
    end
  end

  btnFw.onClick = function()
    vibrate(35)
    if tafMpPrepared then
      pcall(function()
        local dur = mp1.getDuration()
        local pos = mp1.getCurrentPosition() + (seekDuration * 1000)
        if dur and dur > 0 and pos > dur then pos = dur end
        mp1.seekTo(pos)
      end)
    end
  end

  btnRw.onClick = function()
    vibrate(35)
    if tafMpPrepared then
      pcall(function()
        local pos = math.max(0, mp1.getCurrentPosition() - (seekDuration * 1000))
        mp1.seekTo(pos)
      end)
    end
  end

  seek.setOnSeekBarChangeListener(SeekBar.OnSeekBarChangeListener{
    onProgressChanged = function(sb,p,fu)
      if fu and tvSt then tvSt.setText("Seek: "..p.."%") end
    end,
    onStartTrackingTouch = function(sb) end,
    onStopTrackingTouch = function(sb)
      local pct = sb.getProgress()
      if tafMpPrepared then
        pcall(function()
          local dur = mp1.getDuration()
          if dur and dur > 0 then
            local targetMs = math.floor((pct / 100) * dur)
            mp1.seekTo(targetMs)
            tvSt.setText("Seeked to " .. formatMs(targetMs) .. " (" .. pct .. "%)")
          end
        end)
      end
    end
  })

  btnClose.onClick = function()
    vibrate(35)
    d.dismiss()
  end

  btnCpy.onClick = function()
    vibrate(35)
    if fullTextForCopy == "" then Toast.makeText(activity,"Tafseer not loaded yet",Toast.LENGTH_SHORT).show() return end
    copyTextToJieshuo(fullTextForCopy, "Tafseer")
    Toast.makeText(activity,"Tafseer copied!",Toast.LENGTH_SHORT).show()
  end

  btnDlTaf.onClick = function()
    vibrate(38)
    if not tafCurrentAudioUrl then
      Toast.makeText(activity, "Audio link not loaded yet. Tap PLAY AUDIO to fetch link.", Toast.LENGTH_SHORT).show()
      return
    end
    pcall(function()
      local dm = activity.getSystemService(Context.DOWNLOAD_SERVICE)
      local req = DownloadManager.Request(Uri.parse(tafCurrentAudioUrl))
      req.setTitle("Tafseer Ibn Kathir Surah " .. surahNames[sIdx])
      req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
      local ss = surahNames[sIdx]:gsub("[" .. string.char(94) .. "%w]", "")
      req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Quran_Tafseer/Tafseer_Ibn_Kathir_Surah" .. string.format("%03d", sIdx) .. string.char(95) .. ss .. ".mp3")
      dm.enqueue(req)
      Toast.makeText(activity, "Tafseer MP3 Download started!", Toast.LENGTH_LONG).show()
    end)
  end

  tafCon.addView(loadlayout({TextView,text="Loading Tafseer...",textSize=afs,textColor=0xFF7DD3FC,gravity="center",padding="25dp"}))

  local arCacheKey = "surah_ar" .. string.char(95) .. sIdx .. ".json"
  local tfCacheKey = "tafseer_ibnkathir_ur" .. string.char(95) .. sIdx .. ".json"
  local cachedAr = readCache(arCacheKey)
  local cachedTf = readCache(tfCacheKey)
  local cachedMeta = readCache(metaCacheKey)

  task(function(s, cAr, cTf, cM)
    local function f(u, timeoutMs)
      local ok,res = pcall(function()
        local url=URL(u)
        local c=url.openConnection()
        c.setRequestMethod("GET")
        c.setRequestProperty("User-Agent","Mozilla/5.0")
        c.setConnectTimeout(timeoutMs or 15000)
        c.setReadTimeout(timeoutMs or 15000)
        if c.getResponseCode() == 200 then
          local sc=Scanner(c.getInputStream(),"UTF-8")
          sc.useDelimiter(string.char(92) .. "A")
          local t=sc.hasNext() and sc.next() or ""
          sc.close()
          return t
        end
        return nil
      end)
      return ok and res or nil
    end
    local ar = cAr or f("https://api.alquran.cloud/v1/surah/"..s, 10000)
    local tf = cTf or f("https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/ur-tafseer-ibn-e-kaseer/"..s..".json", 20000)
    if not tf then
      tf = f("https://raw.githubusercontent.com/spa5k/tafsir_api/main/tafsir/ur-tafseer-ibn-e-kaseer/"..s..".json", 20000)
    end
    local m = cM or f("https://archive.org/metadata/Tafsir-ibne-kaseer-kathir-urdu-----audio-mp3-hq", 12000)
    return ar, tf, m
  end, sIdx, cachedAr, cachedTf, cachedMeta, function(arJ, tfJ, metaJ)
    if not dialogOpen then return end
    if arJ and not cachedAr then writeCache(arCacheKey, arJ) end
    if tfJ and not cachedTf then writeCache(tfCacheKey, tfJ) end
    if metaJ and not cachedMeta then writeCache(metaCacheKey, metaJ) end

    tafCurrentAudioUrl = parseArchiveSurahUrl(metaJ, "Tafsir-ibne-kaseer-kathir-urdu-----audio-mp3-hq", sIdx)
    if tafCurrentAudioUrl then
      if pendingSeekMs > 0 then
        tvSt.setText("Ready: Tafseer Ibn Kathir - Resume at " .. formatMs(pendingSeekMs))
      else
        tvSt.setText("Ready: Tafseer Ibn Kathir - Tap PLAY AUDIO")
      end
    else
      tvSt.setText("Audio link not loaded - Tap PLAY AUDIO to retry")
    end

    tafCon.removeAllViews()
    if not tfJ then
      tafCon.addView(loadlayout({TextView,text="Written Tafseer network error. You can still tap PLAY AUDIO to listen.",textSize=afs,textColor=0xFFFBBF24,gravity="center",padding="20dp"}))
      return
    end

    local arAy={}
    if arJ then
      pcall(function()
        local o=JSONObject(arJ)
        local dd=o.getJSONObject("data")
        local a=dd.getJSONArray("ayahs")
        for i=0,a.length()-1 do
          local x=a.getJSONObject(i)
          table.insert(arAy,cleanText(x.getString("text")))
        end
      end)
    end

    local tfs={}
    pcall(function()
      local o=JSONObject(tfJ)
      local a=o.getJSONArray("ayahs")
      for i=0,a.length()-1 do
        local x=a.getJSONObject(i)
        local t=x.getString("text")
        local n=i+1
        pcall(function() n=x.getInt("ayah") end)
        table.insert(tfs,{ayah=n,text=cleanTaf(t)})
      end
    end)

    if #tfs == 0 then
      tafCon.addView(loadlayout({TextView,text="Tafseer text could not be parsed.",textSize=afs,textColor=0xFFEF4444,gravity="center",padding="20dp"}))
      return
    end

    table.sort(tfs, function(a, b) return (a.ayah or 0) < (b.ayah or 0) end)

    local allSameTaf = (#tfs > 1)
    if allSameTaf then
      local firstTxt = tfs[1].text or ""
      for i = 2, #tfs do
        if (tfs[i].text or "") ~= firstTxt then allSameTaf = false break end
      end
      if firstTxt == "" then allSameTaf = false end
    end

    local copyParts={}
    if allSameTaf then
      table.insert(copyParts, "Surah " .. surahNames[sIdx] .. " Complete Tafseer Ibn Kathir:\n\n" .. tfs[1].text)
      tafCon.addView(loadlayout({
        LinearLayout,orientation="vertical",layout_width="fill",
        background=brd(0xFF16213E,0xFF2563EB,16),padding="18dp",
        {
          LinearLayout,orientation="vertical",layout_width="fill",
          background=brd(0xFF0B1220,0xFF1E40AF,10),padding="12dp",
          {TextView,text="Surah "..surahNames[sIdx].." Complete Tafseer",textSize="16sp",textColor=0xFFFBBF24,typeface=Typeface.DEFAULT_BOLD,gravity="center"},
          {View,layout_width="fill",layout_height="6dp"},
          {TextView,text="(Comprehensive Tafseer for All Ayahs)",textSize="11sp",textColor=0xFF7DD3FC,gravity="center"}
        },
        {View,layout_width="fill",layout_height="12dp"},
        {TextView,text=tfs[1].text,textSize=afs,textColor=0xFFE2E8F0,gravity="right"}
      }))
    else
      for idx, it in ipairs(tfs) do
        if it.text and it.text ~= "" then
          local at = ""
          if arAy[it.ayah] then at = arAy[it.ayah] end
          table.insert(copyParts, "Ayah " .. it.ayah .. ":\n" .. (at ~= "" and (at .. "\n") or "") .. it.text)
          local ch = {
            {TextView,text="Ayah " .. it.ayah,textSize="15sp",textColor=0xFFFBBF24,typeface=Typeface.DEFAULT_BOLD,gravity="right"},
            {View,layout_width="fill",layout_height="10dp"}
          }
          if at ~= "" then
            table.insert(ch,{
              LinearLayout,orientation="vertical",layout_width="fill",
              background=brd(0xFF0B1220,0xFF1E40AF,10),padding="12dp",
              {TextView,text=at,textSize=aafs,textColor=0xFF7DD3FC,gravity="right",typeface=Typeface.DEFAULT_BOLD}
            })
            table.insert(ch,{View,layout_width="fill",layout_height="12dp"})
          end
          table.insert(ch,{TextView,text=it.text,textSize=afs,textColor=0xFFE2E8F0,gravity="right"})

          local cardLayout = {
            LinearLayout,orientation="vertical",layout_width="fill",
            background=brd(0xFF16213E,0xFF2563EB,16),padding="18dp"
          }
          for idx, item in ipairs(ch) do
            table.insert(cardLayout, item)
          end
          tafCon.addView(loadlayout(cardLayout))
          tafCon.addView(loadlayout({View,layout_width="fill",layout_height="12dp"}))
        end
      end
    end
    fullTextForCopy = table.concat(copyParts, "\n\n---\n\n")
  end)
end

function showSurahPopup(sIdx, autoMode, forcedStartAyah)
  vibrate(38)
  cS = sIdx
  local afs = (textSizeEnabled and textSizeVal or 15).."sp"
  local paraStart, paraEnd, paraNum, pageFilter = getEffectiveRange(sIdx)

  if forcedStartAyah and forcedStartAyah >= 1 and forcedStartAyah <= surahCounts[sIdx] then
    cA = forcedStartAyah
  elseif resumeEnabled and pref.getInt("lastSurah",1) == sIdx then
    local savedA = pref.getInt("lastAyah", paraStart)
    if savedA >= paraStart and savedA <= paraEnd then
      cA = savedA
    else
      cA = paraStart
    end
  else
    cA = paraStart
  end

  currentRepeatTracker = 1
  surahRepeatTracker = 1
  playMode = autoMode or "none"
  rukuEndAyah = 0
  customRangeStart = 0
  customRangeEnd = 0
  customRangeRepeats = 1
  singlePlaying = false
  currentRukuPos = -1
  currentRukuView = nil
  local ayahViewMap = {}

  stopAudioOnly()
  clearHighlight()

  local function highlightAndScrollAyah(ayahNum)
    local entry = ayahViewMap[ayahNum]
    if entry and entry.view then
      clearHighlight()
      setHighlight(entry.view)
      currentAyahView = entry.view
      currentAyahPos = entry.pos
      pcall(function()
        pScroll.post(Runnable({
          run = function()
            pcall(function()
              local y = lstContainer.getTop() + entry.view.getTop() - 80
              if y < 0 then y = 0 end
              pScroll.smoothScrollTo(0, y)
            end)
          end
        }))
      end)
    end
  end

  local filterBannerText = nil
  if pageFilter then
    filterBannerText = "Showing Page " .. pageFilter .. " (Para " .. (paraNum or 1) .. ")"
  elseif paraNum then
    filterBannerText = "Showing Para " .. paraNum .. "  (Ayahs " .. paraStart .. " - " .. paraEnd .. ")"
  end

  local pl = {
    ScrollView, id="pScroll", layout_width="fill", layout_height="fill", fillViewport=true,
    {
      LinearLayout,orientation="vertical",layout_width="fill",padding="18dp",
      background=grad(0xFF0B1220,0xFF16213E,28),
      {
        LinearLayout,orientation="vertical",layout_width="fill",padding="16dp",
        background=brd(0xFF1E3A5F,0xFF7DD3FC,20),
        {TextView,id="tvTitle",text=sIdx..".  "..surahNames[sIdx],textSize="21sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD,gravity="center"},
        {View,layout_width="fill",layout_height="8dp"},
        {
          LinearLayout,orientation="horizontal",gravity="center",layout_width="fill",
          {TextView,text=(surahTypes[sIdx] == "M" and "Makki" or "Madani"),textSize="12sp",textColor=0xFF94A3B8,typeface=Typeface.DEFAULT_BOLD},
          {TextView,text="     ",textSize="12sp"},
          {TextView,text=surahCounts[sIdx].." Ayahs",textSize="12sp",textColor=0xFF94A3B8,typeface=Typeface.DEFAULT_BOLD},
          {TextView,text="     ",textSize="12sp"},
          {TextView,text=surahRuku[sIdx].." Ruku",textSize="12sp",textColor=0xFF94A3B8,typeface=Typeface.DEFAULT_BOLD}
        },
        (filterBannerText and {
          TextView,
          text=filterBannerText,
          textSize="12sp",textColor=0xFFFBBF24,gravity="center",typeface=Typeface.DEFAULT_BOLD,
          paddingTop="8dp"
        } or {View,layout_width="fill",layout_height="0dp"})
      },
      {View,layout_width="fill",layout_height="12dp"},
      {
        LinearLayout,orientation="horizontal",layout_width="fill",
        {Button,id="btnBmAdd",text="BOOKMARK",background=grad(0xFFD97706,0xFFB45309,18),textColor=0xFFFFFFFF,textSize="10sp",layout_weight=1,layout_height="40dp",typeface=Typeface.DEFAULT_BOLD},
        {View,layout_width="6dp",layout_height="fill"},
        {Button,id="btnHifzRange",text="RANGE REPEAT",background=grad(0xFF2563EB,0xFF1E40AF,18),textColor=0xFFFFFFFF,textSize="10sp",layout_weight=1,layout_height="40dp",typeface=Typeface.DEFAULT_BOLD},
        {View,layout_width="6dp",layout_height="fill"},
        {Button,id="btnQuickTimer",text="TIMER",background=grad(0xFF475569,0xFF334155,18),textColor=0xFFFFFFFF,textSize="10sp",layout_weight=1,layout_height="40dp",typeface=Typeface.DEFAULT_BOLD}
      },
      {View,layout_width="fill",layout_height="10dp"},
      {
        LinearLayout,orientation="horizontal",layout_width="fill",padding="12dp",
        background=brd(0xFF16213E,0xFF2563EB,14),
        {TextView,text="Reciter",textSize="12sp",textColor=0xFF7DD3FC,layout_gravity="center",typeface=Typeface.DEFAULT_BOLD},
        {View,layout_width="10dp",layout_height="fill"},
        {Spinner,id="spR",layout_width="0dp",layout_weight="1",layout_height="42dp"}
      },
      {View,layout_width="fill",layout_height="8dp"},
      {
        LinearLayout,orientation="horizontal",layout_width="fill",padding="12dp",
        background=brd(0xFF16213E,0xFF7C3AED,14),
        {TextView,text="Translation",textSize="12sp",textColor=0xFF7DD3FC,layout_gravity="center",typeface=Typeface.DEFAULT_BOLD},
        {View,layout_width="10dp",layout_height="fill"},
        {Spinner,id="spT",layout_width="0dp",layout_weight="1",layout_height="42dp"}
      },
      {View,layout_width="fill",layout_height="12dp"},
      {
        LinearLayout,orientation="horizontal",layout_width="fill",
        {Button,id="btnRd",text="READ AND COPY TEXT",background=grad(0xFF0EA5E9,0xFF0369A1,20),textColor=0xFFFFFFFF,textSize="11sp",layout_weight=1,layout_height="46dp",typeface=Typeface.DEFAULT_BOLD},
        {View,layout_width="8dp",layout_height="fill"},
        {Button,id="btnTf",text="READ AND PLAY TAFSEER",background=grad(0xFF7C3AED,0xFF5B21B6,20),textColor=0xFFFFFFFF,textSize="11sp",layout_weight=1,layout_height="46dp",typeface=Typeface.DEFAULT_BOLD}
      },
      {View,layout_width="fill",layout_height="10dp"},
      {Button,id="btnA",text="PLAY FULL SURAH (ARABIC)",background=grad(0xFF059669,0xFF065F46,22),textColor=0xFFFFFFFF,textSize="12sp",typeface=Typeface.DEFAULT_BOLD,layout_width="fill",layout_height="48dp"},
      {View,layout_width="fill",layout_height="8dp"},
      {Button,id="btnTr",text="PLAY FULL SURAH (TRANSLATION)",background=grad(0xFF0891B2,0xFF155E75,22),textColor=0xFFFFFFFF,textSize="12sp",typeface=Typeface.DEFAULT_BOLD,layout_width="fill",layout_height="48dp"},
      {View,layout_width="fill",layout_height="10dp"},
      {
        LinearLayout,id="lc",orientation="vertical",layout_width="fill",
        background=brd(0xFF0F2027,0xFF2563EB,16),padding="10dp",
        visibility=(playMode == "full_arabic" or playMode == "full_trans" or playMode == "range_repeat") and View.VISIBLE or View.GONE,
        {
          LinearLayout,orientation="horizontal",gravity="center",layout_width="fill",
          {Button,id="btnPv",text="Previous",textSize="10sp",background=grad(0xFF334155,0xFF1E293B,14),textColor=0xFFF1F5F9,layout_weight=1,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="4dp",layout_height="fill"},
          {Button,id="btnRw",text="-"..seekDuration.."s",textSize="10sp",background=grad(0xFF334155,0xFF1E293B,14),textColor=0xFFF1F5F9,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="4dp",layout_height="fill"},
          {Button,id="btnPP",text="Pause",textSize="10sp",typeface=Typeface.DEFAULT_BOLD,background=grad(0xFF2563EB,0xFF1E40AF,14),textColor=0xFFFFFFFF},
          {View,layout_width="4dp",layout_height="fill"},
          {Button,id="btnFw",text="+"..seekDuration.."s",textSize="10sp",background=grad(0xFF334155,0xFF1E293B,14),textColor=0xFFF1F5F9,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="4dp",layout_height="fill"},
          {Button,id="btnNx",text="Next",textSize="10sp",background=grad(0xFF334155,0xFF1E293B,14),textColor=0xFFF1F5F9,layout_weight=1,typeface=Typeface.DEFAULT_BOLD}
        }
      },
      {View,layout_width="fill",layout_height="12dp"},
      {TextView,id="tvListHead",text="Loading...",textSize="12sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD,gravity="center"},
      {View,layout_width="fill",layout_height="8dp"},
      {LinearLayout,id="lstContainer",orientation="vertical",layout_width="fill"},
      {View,layout_width="fill",layout_height="12dp"},
      {
        LinearLayout,orientation="vertical",layout_width="fill",padding="12dp",
        background=brd(0xFF16213E,0xFF2563EB,14),
        {TextView,id="tvS",text="Nothing is playing",textSize="12sp",textColor=0xFFCBD5E1,gravity="center"}
      },
      {View,layout_width="fill",layout_height="12dp"},
      {Button,id="btnDl",text="DOWNLOAD FULL SURAH MP3",background=grad(0xFF0EA5E9,0xFF0369A1,22),textColor=0xFFFFFFFF,textSize="12sp",typeface=Typeface.DEFAULT_BOLD,layout_width="fill",layout_height="46dp"},
      {View,layout_width="fill",layout_height="8dp"},
      {Button,id="btnCl",text="CLOSE",background=grad(0xFF334155,0xFF1E293B,24),textColor=0xFFF1F5F9,textSize="13sp",layout_width="fill",layout_height="46dp",typeface=Typeface.DEFAULT_BOLD}
    }
  }
  local d = AlertDialog.Builder(activity).setView(loadlayout(pl)).create()
  pcall(function()
    local w = d.getWindow()
    w.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
    local dm = activity.getResources().getDisplayMetrics()
    local lp = w.getAttributes()
    lp.width = math.floor(dm.widthPixels * 0.94)
    lp.height = math.floor(dm.heightPixels * 0.88)
    w.setAttributes(lp)
  end)
  local transitioningNextSurah = false
  d.setOnDismissListener(DialogInterface.OnDismissListener{
    onDismiss = function()
      if transitioningNextSurah then return end
      pcall(function()
        if mp1.isPlaying() then
          lastPlaybackPosition = mp1.getCurrentPosition()
          savePreferences()
        end
      end)
      if not backgroundAudio then
        stopAll()
      end
    end
  })
  d.show()

  btnCl.onClick = function()
    vibrate(35)
    pcall(function()
      if mp1.isPlaying() then
        lastPlaybackPosition = mp1.getCurrentPosition()
      end
    end)
    savePreferences()
    if not backgroundAudio then
      stopAll()
    end
    d.dismiss()
  end

  btnQuickTimer.onClick = function() showSleepTimerDialog() end

  btnBmAdd.onClick = function()
    vibrate(35)
    local added = addBookmark(cS, cA, "Saved at Ayah " .. cA)
    if added then
      Toast.makeText(activity, "Bookmarked Surah " .. surahNames[cS] .. " (Ayah " .. cA .. ")", Toast.LENGTH_SHORT).show()
    else
      Toast.makeText(activity, "Already bookmarked! Opening Bookmarks...", Toast.LENGTH_SHORT).show()
      showBookmarksDialog(d)
    end
  end

  local function startFull()
    stopAudioOnly()
    local mySession = playbackSession
    local useT = (playMode == "full_trans")
    btnPP.setText("Pause")
    local rp = 0
    if resumeEnabled then rp = lastPlaybackPosition end
    local startLimit = paraStart
    local endLimit = paraEnd
    if rukuEndAyah > 0 then
      endLimit = rukuEndAyah
    elseif playMode == "range_repeat" and customRangeStart > 0 and customRangeEnd >= customRangeStart then
      startLimit = customRangeStart
      endLimit = customRangeEnd
    end

    local function step(ni)
      if mySession ~= playbackSession then return end
      if ni > endLimit then
        if rukuEndAyah > 0 then
          tvS.setText("Ruku completed")
          playMode = "none"
          lc.setVisibility(View.GONE)
          btnPP.setText("Pause")
          rukuEndAyah = 0
          clearHighlight()
          return
        end
        if playMode == "range_repeat" then
          if surahRepeatTracker < customRangeRepeats then
            surahRepeatTracker = surahRepeatTracker + 1
            tvS.setText("Range Repeat ("..surahRepeatTracker.."/"..customRangeRepeats..")")
            step(startLimit)
          else
            tvS.setText("Range Repeat completed")
            playMode = "none"
            lc.setVisibility(View.GONE)
            btnPP.setText("Pause")
            clearHighlight()
          end
          return
        end
        if repeatEnabled and surahRepeatTracker < repeatCount then
          surahRepeatTracker = surahRepeatTracker + 1
          tvS.setText("Repeating ("..surahRepeatTracker.."/"..repeatCount..")")
          step(startLimit)
          return
        end
        if cS < 114 and not paraModeEnabled and not pageModeEnabled then
          local cm = playMode
          transitioningNextSurah = true
          d.dismiss()
          task(400, function() showSurahPopup(cS+1, cm) end)
        else
          tvS.setText("Completed")
          playMode = "none"
          lc.setVisibility(View.GONE)
          btnPP.setText("Pause")
          clearHighlight()
        end
        return
      end
      cA = ni
      lastSurah = cS
      lastAyah = cA
      lastPlaybackPosition = 0
      savePreferences()
      local m = "Recitation"
      if playMode == "full_trans" then m = "Translation" end
      if playMode == "ruku" then m = "Ruku Recitation" end
      if playMode == "range_repeat" then m = "Range ("..customRangeStart.."-"..customRangeEnd..") ["..surahRepeatTracker.."/"..customRangeRepeats.."]" end
      tvS.setText(m..": Ayah "..cA)
      local r = reciters[reciterIdx+1]
      if not r.ayahByAyah and not useT then
        pcall(function()
          mp1.reset()
          mp1.setDataSource(r.server..string.format("%03d.mp3",cS))
          mp1.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
            if mySession ~= playbackSession then return end
            applySpeed(p)
            p.start()
            if rp > 0 then p.seekTo(rp) rp=0 end
          end})
          mp1.setOnCompletionListener(MediaPlayer.OnCompletionListener{onCompletion=function()
            if mySession ~= playbackSession then return end
            if cS < 114 then
              local cm = playMode
              transitioningNextSurah = true
              d.dismiss()
              task(400, function() showSurahPopup(cS+1, cm) end)
            else
              playMode = "none"
            end
          end})
          mp1.prepareAsync()
        end)
        return
      end

      if playMode ~= "ruku" then
        onUI(function() highlightAndScrollAyah(cA) end)
      end

      pcall(function()
        mp1.reset()
        mp1.setDataSource(getUrl(cS,cA,useT))
        mp1.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
          if mySession ~= playbackSession then return end
          applySpeed(p)
          p.start()
        end})
        mp1.setOnCompletionListener(MediaPlayer.OnCompletionListener{onCompletion=function()
          if mySession ~= playbackSession then return end
          step(cA+1)
        end})
        mp1.prepareAsync()
      end)
    end
    step(cA)
  end

  btnHifzRange.onClick = function()
    vibrate(35)
    local rNow = reciters[reciterIdx+1]
    if not rNow.ayahByAyah then
      Toast.makeText(activity, "Please select an Ayah-by-Ayah reciter for Range Repeat", Toast.LENGTH_LONG).show()
      return
    end
    local rl = {
      LinearLayout, orientation="vertical", layout_width="fill", padding="20dp",
      background=grad(0xFF0B1220,0xFF16213E,24),
      {TextView, text="CUSTOM AYAH RANGE (HIFZ)", textSize="17sp", textColor=0xFF7DD3FC, typeface=Typeface.DEFAULT_BOLD, gravity="center"},
      {View, layout_width="fill", layout_height="6dp"},
      {TextView, text="Surah "..surahNames[sIdx].." (Ayahs 1 - "..surahCounts[sIdx]..")", textSize="12sp", textColor=0xFFFBBF24, gravity="center"},
      {View, layout_width="fill", layout_height="14dp"},
      {
        LinearLayout, orientation="horizontal", layout_width="fill", gravity="center_vertical",
        {TextView, text="From Ayah: ", textColor=0xFFF1F5F9, textSize="13sp", layout_weight="1"},
        {EditText, id="etFromAyah", text=tostring(paraStart), inputType=2, layout_width="100dp", layout_height="42dp", textColor=0xFFF1F5F9, gravity="center", background=brd(0xFF16213E,0xFF2563EB,12)}
      },
      {View, layout_width="fill", layout_height="10dp"},
      {
        LinearLayout, orientation="horizontal", layout_width="fill", gravity="center_vertical",
        {TextView, text="To Ayah: ", textColor=0xFFF1F5F9, textSize="13sp", layout_weight="1"},
        {EditText, id="etToAyah", text=tostring(math.min(paraStart + 4, paraEnd)), inputType=2, layout_width="100dp", layout_height="42dp", textColor=0xFFF1F5F9, gravity="center", background=brd(0xFF16213E,0xFF2563EB,12)}
      },
      {View, layout_width="fill", layout_height="10dp"},
      {
        LinearLayout, orientation="horizontal", layout_width="fill", gravity="center_vertical",
        {TextView, text="Repeat Times: ", textColor=0xFFF1F5F9, textSize="13sp", layout_weight="1"},
        {EditText, id="etRangeRep", text="3", inputType=2, layout_width="100dp", layout_height="42dp", textColor=0xFFF1F5F9, gravity="center", background=brd(0xFF16213E,0xFF2563EB,12)}
      },
      {View, layout_width="fill", layout_height="16dp"},
      {Button, id="btnStartRange", text="START RANGE LOOP", layout_width="fill", layout_height="46dp", background=grad(0xFF059669,0xFF065F46,22), textColor=0xFFFFFFFF, textSize="13sp", typeface=Typeface.DEFAULT_BOLD}
    }
    local rd = AlertDialog.Builder(activity).setView(loadlayout(rl)).create()
    pcall(function() rd.getWindow().setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT)) end)
    rd.show()

    btnStartRange.onClick = function()
      vibrate(35)
      local fA = tonumber(etFromAyah.getText().toString()) or 1
      local tA = tonumber(etToAyah.getText().toString()) or surahCounts[sIdx]
      local rC = tonumber(etRangeRep.getText().toString()) or 1
      if fA < 1 then fA = 1 end
      if tA > surahCounts[sIdx] then tA = surahCounts[sIdx] end
      if tA < fA then tA = fA end
      if rC < 1 then rC = 1 end

      customRangeStart = fA
      customRangeEnd = tA
      customRangeRepeats = rC
      surahRepeatTracker = 1
      rukuEndAyah = 0
      cA = fA
      playMode = "range_repeat"
      lc.setVisibility(View.VISIBLE)
      rd.dismiss()
      startFull()
    end
  end

  local function handleSingleFinish(mySession)
    if mySession ~= playbackSession then return end
    if repeatEnabled and currentRepeatTracker < repeatCount then
      currentRepeatTracker = currentRepeatTracker + 1
      playSingleAyah()
    else
      currentRepeatTracker = 1
      singlePlaying = false
      tvS.setText("Ayah "..cA.." finished")
      clearHighlight()
    end
  end

  function playSingleAyah()
    stopAudioOnly()
    local mySession = playbackSession
    local r = reciters[reciterIdx+1]

    local playArabic = not translationOnly
    local playTranslation = not arabicOnly

    if playArabic and not r.ayahByAyah then
      if translationOnly then
        playArabic = false
      else
        tvS.setText("Ayah audio not available for this reciter. Please use PLAY FULL SURAH or select another reciter.")
        return
      end
    end

    singlePlaying = true
    lastSurah = cS
    lastAyah = cA
    savePreferences()

    local function playTranslationNow()
      if not playTranslation then
        handleSingleFinish(mySession)
        return
      end
      local ut = getUrl(cS,cA,true)
      pcall(function()
        mp2.reset()
        mp2.setDataSource(ut)
        mp2.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
          if mySession ~= playbackSession then return end
          applySpeed(p)
          p.start()
        end})
        mp2.setOnCompletionListener(MediaPlayer.OnCompletionListener{
          onCompletion=function()
            if mySession ~= playbackSession then return end
            if not singlePlaying then return end
            handleSingleFinish(mySession)
          end
        })
        mp2.prepareAsync()
      end)
    end

    if playArabic then
      local ua = getUrl(cS,cA,false)
      if not ua then
        playArabic = false
      else
        pcall(function()
          mp1.reset()
          mp1.setDataSource(ua)
          mp1.setOnPreparedListener(MediaPlayer.OnPreparedListener{onPrepared=function(p)
            if mySession ~= playbackSession then return end
            applySpeed(p)
            p.start()
          end})
          mp1.setOnCompletionListener(MediaPlayer.OnCompletionListener{
            onCompletion=function()
              if mySession ~= playbackSession then return end
              if not singlePlaying then return end
              playTranslationNow()
            end
          })
          mp1.prepareAsync()
        end)
        if playTranslation then
          tvS.setText("Playing Ayah "..cA.." (Arabic + Translation)")
        else
          tvS.setText("Playing Ayah "..cA.." (Arabic)")
        end
        return
      end
    end

    playTranslationNow()
    tvS.setText("Playing Ayah "..cA.." (Translation only)")
  end

  local cachedSurahJson = nil
  local function renderAyahListFromJson(arJ)
    lstContainer.removeAllViews()
    ayahViewMap = {}
    local currentReciter = reciters[reciterIdx+1]
    local supportsAyah = currentReciter and currentReciter.ayahByAyah

    if not supportsAyah and not translationOnly then
      tvListHead.setText("Notice")
      pcall(function()
        lstContainer.addView(loadlayout({
          LinearLayout,orientation="vertical",layout_width="fill",padding="24dp",
          background=brd(0xFF16213E,0xFFFBBF24,18),
          {TextView,text="Full Surah Only",textSize="16sp",textColor=0xFFFBBF24,typeface=Typeface.DEFAULT_BOLD,gravity="center"},
          {View,layout_width="fill",layout_height="10dp"},
          {TextView,text=currentReciter.name.." only has full Surah audio. Individual Ayah playback is not available for this reciter.",textSize="13sp",textColor=0xFFE2E8F0,gravity="center"},
          {View,layout_width="fill",layout_height="10dp"},
          {TextView,text="Please use PLAY FULL SURAH (ARABIC) button, or select a different reciter to play individual ayahs.",textSize="12sp",textColor=0xFF7DD3FC,gravity="center"}
        }))
      end)
      return
    end

    if not arJ then
      tvListHead.setText("Network error - Retry")
      return
    end
    local ayahs = {}
    local rukuMap = {}
    pcall(function()
      local o = JSONObject(arJ)
      local dd = o.getJSONObject("data")
      local a = dd.getJSONArray("ayahs")
      for i=0,a.length()-1 do
        local x = a.getJSONObject(i)
        local num = i+1
        pcall(function() num = x.getInt("numberInSurah") end)
        local txt = cleanText(x.getString("text"))
        local ruku = 0
        pcall(function() ruku = x.getInt("ruku") end)
        local pg = 0
        pcall(function() pg = x.getInt("page") end)
        local matchesRange = (num >= paraStart and num <= paraEnd)
        if pageFilter and pg > 0 then
          matchesRange = matchesRange and (pg == pageFilter)
        end
        if matchesRange then
          table.insert(ayahs, {num=num, text=txt, ruku=ruku, page=pg})
          if ruku > 0 then
            if not rukuMap[ruku] then
              rukuMap[ruku] = {start=num, last=num, idx=ruku}
            else
              rukuMap[ruku].last = num
            end
          end
        end
      end
    end)

    if #ayahs > 0 then
      paraStart = ayahs[1].num
      paraEnd = ayahs[#ayahs].num
      if cA < paraStart or cA > paraEnd then cA = paraStart end
    end

    local isRukuList = rukuMode and next(rukuMap) ~= nil

    if isRukuList then
      tvListHead.setText("Tap any Ruku to play. Tap again to stop.")
      local keys = {}
      for k, unused in pairs(rukuMap) do table.insert(keys, k) end
      table.sort(keys)
      for idx, k in ipairs(keys) do
        local rk = rukuMap[k]
        local pos = idx - 1
        local itemView = loadlayout({
          LinearLayout,orientation="vertical",layout_width="fill",padding="12dp",
          background=brd(0xFF16213E,0xFF2563EB,14),
          {TextView,text="Ruku "..k,textSize="12sp",textColor=0xFFFBBF24,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="6dp"},
          {TextView,text="Ayahs "..rk.start.." - "..rk.last,textSize=afs,textColor=0xFFF1F5F9,gravity="right",typeface=Typeface.DEFAULT_BOLD}
        })
        itemView.setFocusable(true)
        itemView.setFocusableInTouchMode(true)
        itemView.setClickable(true)
        itemView.setOnClickListener(View.OnClickListener{onClick=function(v)
          vibrate(38)
          if currentRukuPos == pos and playMode == "ruku" then
            stopAudioOnly()
            clearHighlight()
            rukuEndAyah = 0
            playMode = "none"
            tvS.setText("Stopped - Ruku "..k)
            return
          end
          stopAudioOnly()
          clearHighlight()
          currentRukuPos = pos
          currentRukuView = v
          cA = rk.start
          rukuEndAyah = rk.last
          playMode = "ruku"
          lc.setVisibility(View.GONE)
          setHighlight(v)
          currentAyahView = v
          startFull()
        end})
        lstContainer.addView(itemView)
        lstContainer.addView(loadlayout({View,layout_width="fill",layout_height="6dp"}))
      end
    else
      tvListHead.setText("Tap any Ayah to play. Tap again to stop.")
      for idx, ay in ipairs(ayahs) do
        local pos = idx - 1
        local itemView = loadlayout({
          LinearLayout,orientation="vertical",layout_width="fill",padding="12dp",
          background=brd(0xFF16213E,0xFF2563EB,14),
          {TextView,text="Ayah "..ay.num..(ay.page and ay.page > 0 and ("  -  Page "..ay.page) or ""),textSize="12sp",textColor=0xFFFBBF24,typeface=Typeface.DEFAULT_BOLD},
          {View,layout_width="fill",layout_height="6dp"},
          {TextView,text=ay.text,textSize=afs,textColor=0xFFF1F5F9,gravity="right",typeface=Typeface.DEFAULT_BOLD}
        })
        ayahViewMap[ay.num] = {view = itemView, pos = pos}
        itemView.setFocusable(true)
        itemView.setFocusableInTouchMode(true)
        itemView.setClickable(true)
        itemView.setOnClickListener(View.OnClickListener{onClick=function(v)
          vibrate(38)
          local rNow = reciters[reciterIdx+1]
          if not rNow.ayahByAyah and not translationOnly then
            tvS.setText("Ayah audio not available for this reciter")
            return
          end

          if currentAyahPos == pos and singlePlaying then
            stopAudioOnly()
            clearHighlight()
            tvS.setText("Stopped - Ayah "..(ay.num))
            return
          end

          stopAudioOnly()
          clearHighlight()
          playMode = "single"
          lc.setVisibility(View.GONE)
          cA = ay.num
          currentRepeatTracker = 1
          setHighlight(v)
          currentAyahView = v
          currentAyahPos = pos
          playSingleAyah()
        end})
        lstContainer.addView(itemView)
        lstContainer.addView(loadlayout({View,layout_width="fill",layout_height="6dp"}))
      end
      if forcedStartAyah or (resumeEnabled and cA > paraStart) then
        highlightAndScrollAyah(cA)
      end
    end
  end

  local arCacheKey = "surah_ar" .. string.char(95) .. sIdx .. ".json"
  cachedSurahJson = readCache(arCacheKey)
  if cachedSurahJson then
    renderAyahListFromJson(cachedSurahJson)
  else
    task(function(s)
      local ok,res = pcall(function()
        local url=URL("https://api.alquran.cloud/v1/surah/"..s)
        local c=url.openConnection()
        c.setRequestMethod("GET")
        c.setRequestProperty("User-Agent","Mozilla/5.0")
        c.setConnectTimeout(8000)
        c.setReadTimeout(8000)
        if c.getResponseCode() == 200 then
          local sc=Scanner(c.getInputStream(),"UTF-8")
          sc.useDelimiter(string.char(92) .. "A")
          local t=sc.hasNext() and sc.next() or ""
          sc.close()
          return t
        end
        return nil
      end)
      return ok and res or nil
    end, sIdx, function(arJ)
      if arJ then
        writeCache(arCacheKey, arJ)
        cachedSurahJson = arJ
      end
      renderAyahListFromJson(arJ)
    end)
  end

  local spRInitialized = false
  local rn = {}
  for idx, v in ipairs(reciters) do table.insert(rn,v.name) end
  spR.setAdapter(ArrayAdapter(activity,android.R.layout.simple_spinner_dropdown_item,rn))
  spR.setSelection(reciterIdx)
  spR.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
    onItemSelected=function(p,v,pos,id)
      if not spRInitialized then spRInitialized = true return end
      if reciterIdx ~= pos then
        reciterIdx = pos
        savePreferences()
        stopAll()
        vibrate(35)
        if cachedSurahJson then renderAyahListFromJson(cachedSurahJson) end
      end
    end,
    onNothingSelected=function(p) end
  })

  local spTInitialized = false
  local tn = {}
  for idx, v in ipairs(translators) do table.insert(tn,v.name) end
  spT.setAdapter(ArrayAdapter(activity,android.R.layout.simple_spinner_dropdown_item,tn))
  spT.setSelection(transIdx)
  spT.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
    onItemSelected=function(p,v,pos,id)
      if not spTInitialized then spTInitialized = true return end
      if transIdx ~= pos then
        transIdx = pos
        savePreferences()
        stopAll()
        vibrate(35)
      end
    end,
    onNothingSelected=function(p) end
  })

  if playMode == "full_arabic" or playMode == "full_trans" then startFull() end

  btnRd.onClick = function() vibrate(38) stopAll() d.dismiss() showReader(sIdx) end
  btnTf.onClick = function() vibrate(38) stopAll() d.dismiss() showTafseer(sIdx) end
  btnA.onClick = function() vibrate(38) rukuEndAyah=0 cA=paraStart playMode="full_arabic" lc.setVisibility(View.VISIBLE) startFull() end
  btnTr.onClick = function() vibrate(38) rukuEndAyah=0 cA=paraStart playMode="full_trans" lc.setVisibility(View.VISIBLE) startFull() end

  btnPP.onClick = function()
    vibrate(38)
    pcall(function()
      if mp1.isPlaying() then
        mp1.pause()
        lastPlaybackPosition = mp1.getCurrentPosition()
        savePreferences()
        btnPP.setText("Play")
      else
        if lastPlaybackPosition > 0 then
          mp1.seekTo(lastPlaybackPosition)
        end
        mp1.start()
        btnPP.setText("Pause")
      end
    end)
  end

  btnFw.onClick = function() vibrate(35) pcall(function() mp1.seekTo(mp1.getCurrentPosition() + (seekDuration * 1000)) end) end
  btnRw.onClick = function() vibrate(35) pcall(function() mp1.seekTo(math.max(0, mp1.getCurrentPosition() - (seekDuration * 1000))) end) end
  btnNx.onClick = function() vibrate(38) if cS < 114 then local cm=playMode transitioningNextSurah=true d.dismiss() task(400,function() showSurahPopup(cS+1,cm) end) end end
  btnPv.onClick = function() vibrate(38) if cS > 1 then local cm=playMode transitioningNextSurah=true d.dismiss() task(400,function() showSurahPopup(cS-1,cm) end) end end

  btnDl.onClick = function()
    vibrate(38)
    pcall(function()
      local sr = reciters[reciterIdx+1]
      local url = sr.server..string.format("%03d.mp3",cS)
      local dm = activity.getSystemService(Context.DOWNLOAD_SERVICE)
      local req = DownloadManager.Request(Uri.parse(url))
      req.setTitle("Surah "..surahNames[cS].." ("..sr.name..")")
      req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
      local sn = sr.name:gsub("[" .. string.char(94) .. "%w]", "")
      local ss = surahNames[cS]:gsub("[" .. string.char(94) .. "%w]", "")
      req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Quran/"..sn.."_Surah_"..string.format("%03d",cS).."_"..ss..".mp3")
      dm.enqueue(req)
      Toast.makeText(activity,"Download started!",Toast.LENGTH_LONG).show()
    end)
  end
end

-- ===================================================
-- MAIN LIST & ABOUT (In Pure Professional English)
-- ===================================================
function showMainList()
  vibrate(40)

  local function openWA()
    vibrate(35)
    pcall(function()
      activity.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://wa.me/923124255300?text=Assalam%20o%20Alaikum")))
    end)
  end

  local function showAbout()
    vibrate(38)
    local function card(title, body)
      return {
        LinearLayout,orientation="vertical",layout_width="fill",padding="16dp",
        background=brd(0xFF16213E,0xFF2563EB,16),
        {TextView,text=title,textSize="14sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD},
        {View,layout_width="fill",layout_height="10dp"},
        {TextView,text=body,textSize="12sp",textColor=0xFFE2E8F0}
      }
    end

    local aboutLayout = {
      LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", padding="18dp",
      background=grad(0xFF0B1220,0xFF16213E,28),
      {
        LinearLayout, orientation="vertical", layout_width="fill", padding="16dp",
        background=brd(0xFF1E3A5F,0xFF7DD3FC,20),
        {TextView,text="QURAN AL-KAREEM",textSize="22sp",textColor=0xFF7DD3FC,typeface=Typeface.DEFAULT_BOLD,gravity="center"},
        {View,layout_width="fill",layout_height="4dp"},
        {TextView,text="Developer: Abdul Rehman",textSize="14sp",textColor=0xFFFBBF24,typeface=Typeface.DEFAULT_BOLD,gravity="center"},
        {View,layout_width="fill",layout_height="4dp"},
        {TextView,text="Complete Quran Player and Reader",textSize="12sp",textColor=0xFF94A3B8,gravity="center"}
      },
      {View,layout_width="fill",layout_height="14dp"},
      {
        ScrollView, layout_width="fill", layout_height="0dp", layout_weight="1", fillViewport=true,
        {
          LinearLayout, orientation="vertical", layout_width="fill", paddingRight="4dp",
          card("TOOL OVERVIEW", "A comprehensive Android application for reading, listening, and studying the Holy Quran. It provides high-definition audio recitation by 41 world-renowned reciters, synchronized translation audio in multiple languages, authentic Urdu Tafseer Ibn Kathir with audio streaming, Hifz range repeat, bookmarks, sleep timer, and offline caching."),
          {View,layout_width="fill",layout_height="12dp"},
          card("HOW TO USE", "Step 1: Select or search any Surah from the main list to open it.\n\nStep 2: Choose your desired Reciter and Translation Audio from the dropdown menus.\n\nStep 3: Tap 'PLAY FULL SURAH (ARABIC)' for continuous recitation, or tap any individual Ayah or Ruku to play specific verses.\n\nStep 4: Tap 'READ AND PLAY TAFSEER' to study authentic commentary with audio playback, progress tracking, and full copyable text.\n\nStep 5: Open 'SETTINGS' to customize playback speed, seek intervals, font size, and display filters."),
          {View,layout_width="fill",layout_height="12dp"},
          card("RECITATION & AUDIO", "41 world-renowned reciters with both Ayah-by-Ayah and full Surah audio playback. For reciters that provide full Surah files only, an informative notice is displayed and recitation plays continuously using the full Surah playback button. Single-tap any verse or ruku to play, tap again to stop, and tap once more to replay."),
          {View,layout_width="fill",layout_height="12dp"},
          card("HIFZ RANGE REPEAT", "A dedicated Quran memorization feature for students and Hafiz. Inside any Surah, tap the 'RANGE REPEAT' button to specify a starting Ayah, ending Ayah, and loop count (Repeat Times). The player automatically loops through the selected range to reinforce memorization."),
          {View,layout_width="fill",layout_height="12dp"},
          card("TRANSLATION AUDIO", "7 synchronized audio translation options:\n\n• Urdu: Dr. Farhat Hashmi\n• Urdu: Shamshad Ali Khan\n• English: Ibrahim Walk (Test)\n• English: Sahih International & Ibrahim Walk\n• French: Leclerc\n• Russian: Kuliev\n• Chinese: Chinese Audio\n\nEach verse's translation audio plays right after its Arabic recitation."),
          {View,layout_width="fill",layout_height="12dp"},
          card("TAFSEER IBN KATHIR (AUDIO & TEXT)", "Complete authentic Urdu Tafseer Ibn Kathir (translated by Maulana Muhammad Junagarhi). Features high-quality audio streaming, seek bar with percentage indicators, +/- seek controls, pause and resume memory, full text copying, and one-tap MP3 download."),
          {View,layout_width="fill",layout_height="12dp"},
          card("READER & TEXT COPY", "A clean reading view displaying the full Arabic text alongside your chosen translation. Includes dedicated 'COPY ARABIC TEXT' and 'COPY TRANSLATION' buttons to copy full Surah text to your device clipboard instantly."),
          {View,layout_width="fill",layout_height="12dp"},
          card("FORWARD & REWIND DURATION", "Customizable jump intervals ranging from 5 seconds to 60 seconds (5s, 10s, 15s, 20s, 25s, 30s, 35s, 40s, 45s, 50s, 55s, 60s). Forward and rewind buttons across both the Surah player and Tafseer player dynamically adapt to your chosen interval."),
          {View,layout_width="fill",layout_height="12dp"},
          card("BOOKMARKS SYSTEM", "Bookmark any verse during recitation using the 'BOOKMARK' button. Access your saved verses from the main screen's 'BOOKMARKS' menu, view your saved notes, and tap 'OPEN SURAH' to jump directly to that exact verse."),
          {View,layout_width="fill",layout_height="12dp"},
          card("SLEEP TIMER", "Set an automatic playback timer for 15, 30, 45, or 60 minutes. Playback automatically stops when the timer elapses to conserve your device battery."),
          {View,layout_width="fill",layout_height="12dp"},
          card("OFFLINE CACHE", "Automatically caches opened Surahs, translations, and Tafseer text locally on your device for fast offline reading without an active internet connection. You can clear the cache anytime in Settings."),
          {View,layout_width="fill",layout_height="12dp"},
          card("SURAH, RUKU, PARA & PAGE MODES", "• Ruku Mode: Browse and listen to Surahs grouped by Rukus instead of individual verses.\n\n• Para Mode: Filter Surahs and verses by specific Para (Juz 1 to 30).\n\n• Page Mode: Filter Surahs and verses to match exact Quran pages (1 to 604)."),
          {View,layout_width="fill",layout_height="12dp"},
          card("SETTINGS EXPLAINED", "Detailed overview of all 14 settings:\n\n1. Playback Speed: Adjust recitation speed (0.5x to 2.0x).\n\n2. Forward / Rewind Duration: Set audio jump intervals (5s to 60s).\n\n3. Arabic Only Mode: Play only Arabic recitation, skipping translation.\n\n4. Translation Only Mode: Play only translation audio, skipping Arabic.\n\n5. Ruku Mode: Group and play Surahs by Ruku.\n\n6. Para Mode: Filter by specific Juz (1-30).\n\n7. Page Mode: Filter by exact Quran page (1-604).\n\n8. Resume Playback: Continue audio from where you left off.\n\n9. Background Audio: Keep playing when minimized or screen is off.\n\n10. Offline Cache: Enable local caching and clear cached files.\n\n11. Repeat Full Surah: Loop Surahs with a custom repeat count.\n\n12. Adjust Font Size: Choose from 4 text size presets (14sp to 26sp).\n\n13. Haptic Vibration: Tactile feedback on button presses.\n\n14. Sleep Timer: Set automated playback shutoff timer."),
          {View,layout_width="fill",layout_height="12dp"},
          card("CONTACT AND FEEDBACK", "Feedback, suggestions, and bug reports are welcome. Tap the WhatsApp button below to reach Developer Abdul Rehman directly.")
        }
      },
      {View,layout_width="fill",layout_height="14dp"},
      {Button,text="FEEDBACK VIA WHATSAPP",layout_width="fill",layout_height="48dp",background=grad(0xFF059669,0xFF065F46,24),textColor=0xFFFFFFFF,textSize="12sp",typeface=Typeface.DEFAULT_BOLD,onClick=function() openWA() end},
      {View,layout_width="fill",layout_height="8dp"},
      {Button,id="btnDC",text="CLOSE",layout_width="fill",layout_height="46dp",background=grad(0xFF334155,0xFF1E293B,24),textColor=0xFFF1F5F9,textSize="12sp",typeface=Typeface.DEFAULT_BOLD}
    }
    local d = AlertDialog.Builder(activity).setView(loadlayout(aboutLayout)).create()
    pcall(function()
      local w = d.getWindow()
      w.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
      local dm = activity.getResources().getDisplayMetrics()
      local lp = w.getAttributes()
      lp.width = math.floor(dm.widthPixels * 0.94)
      lp.height = math.floor(dm.heightPixels * 0.88)
      w.setAttributes(lp)
      btnDC.onClick = function() vibrate(35) d.dismiss() end
    end)
    d.show()
  end

  local ml = {
    LinearLayout,orientation="vertical",layout_width="fill",layout_height="fill",backgroundColor=0xFF0B1220,
    {
      LinearLayout,orientation="vertical",layout_width="fill",padding="22dp",
      background=grad(0xFF1E3A5F,0xFF0B1220,0),
      {TextView,id="tvMainTitle",text="Al-Quran Al-Kareem",textSize="26sp",textColor=0xFFF1F5F9,gravity="center",typeface=Typeface.DEFAULT_BOLD,focusable=true,focusableInTouchMode=true},
      {View,layout_width="fill",layout_height="6dp"},
      {TextView,id="tvSubTitle",text="COMPREHENSIVE QURAN PLAYER AND READER",textSize="10sp",textColor=0xFF7DD3FC,gravity="center"}
    },
    {
      LinearLayout,orientation="horizontal",layout_width="fill",padding="12dp",backgroundColor=0xFF0B1220,
      {Button,id="btnSet",text="SETTINGS",layout_width="0dp",layout_weight="1",layout_height="48dp",textSize="12sp",background=grad(0xFF2563EB,0xFF1E40AF,24),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD},
      {View,layout_width="8dp",layout_height="fill"},
      {Button,id="btnBmMain",text="BOOKMARKS",layout_width="0dp",layout_weight="1",layout_height="48dp",textSize="12sp",background=grad(0xFFD97706,0xFFB45309,24),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD}
    },
    {
      LinearLayout,orientation="horizontal",layout_width="fill",paddingLeft="12dp",paddingRight="12dp",paddingBottom="12dp",backgroundColor=0xFF0B1220,
      {EditText,id="etS",hint="Search Surah name or number...",hintTextColor=0xFF64748B,textColor=0xFFF1F5F9,layout_width="fill",layout_height="48dp",textSize="14sp",paddingLeft="20dp",paddingRight="20dp",background=brd(0xFF16213E,0xFF2563EB,24),singleLine=true,imeOptions=EditorInfo.IME_ACTION_SEARCH}
    },
    {ListView,id="lstS",layout_width="fill",layout_height="0dp",layout_weight="1",divider=nil,padding="10dp"},
    {
      LinearLayout,orientation="horizontal",layout_width="fill",padding="12dp",backgroundColor=0xFF0B1220,gravity="center",
      {Button,id="btnAb",text="ABOUT",layout_weight=1,layout_height="46dp",textSize="11sp",background=grad(0xFF0EA5E9,0xFF0369A1,22),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD},
      {View,layout_width="8dp",layout_height="fill"},
      {Button,id="btnEx",text="EXIT",layout_weight=1,layout_height="46dp",textSize="11sp",background=grad(0xFFDC2626,0xFF991B1B,22),textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD}
    }
  }
  activity.setContentView(loadlayout(ml))

  local modeStr = ""
  if pageModeEnabled and paraModeEnabled then
    modeStr = "Para "..selectedPara.."  -  Page "..selectedPage
  elseif pageModeEnabled then
    modeStr = "Page "..selectedPage.." (Para "..pageToPara(selectedPage)..")"
  elseif paraModeEnabled then
    modeStr = "Para "..selectedPara
  end
  if modeStr ~= "" then
    pcall(function() tvSubTitle.setText(modeStr) end)
  end

  task(50,function() pcall(function() if tvMainTitle then tvMainTitle.requestFocus() end end) end)

  etS.setOnEditorActionListener(TextView.OnEditorActionListener{
    onEditorAction=function(v,aid,e)
      if aid == EditorInfo.IME_ACTION_SEARCH or aid == EditorInfo.IME_ACTION_DONE then
        pcall(function()
          local im=activity.getSystemService(Context.INPUT_METHOD_SERVICE)
          if im then im.hideSoftInputFromWindow(v.getWindowToken(),0) end
          if lstS then lstS.requestFocus() end
        end)
        return true
      end
      return false
    end
  })

  local allS = {}
  if pageModeEnabled then
    for i = 1, 114 do
      if sSPage[i] <= selectedPage and sEPage[i] >= selectedPage then
        table.insert(allS, {index=i, displayName="Surah "..surahNames[i].." (Pages "..sSPage[i].."-"..sEPage[i]..")"})
      end
    end
  elseif paraModeEnabled then
    if paraSurahs[selectedPara] then
      for idx, item in ipairs(paraSurahs[selectedPara]) do
        table.insert(allS, {index=item[1], displayName="Surah "..surahNames[item[1]].." (Ayahs "..item[2].."-"..item[3]..")"})
      end
    end
  else
    for i,n in ipairs(surahNames) do
      table.insert(allS,{index=i, displayName="Surah "..n})
    end
  end

  local function loadF(ft)
    local dl,ri = {},{}
    for idx, it in ipairs(allS) do
      local s = it.displayName
      if ft == "" or string.find(string.lower(s),string.lower(ft)) or string.find(tostring(it.index),ft) then
        table.insert(dl,{tvN=tostring(it.index),tvM=it.displayName})
        table.insert(ri,it.index)
      end
    end
    local il = {
      LinearLayout,orientation="horizontal",layout_width="fill",padding="6dp",
      {
        LinearLayout,orientation="horizontal",layout_width="fill",padding="14dp",
        background=brd(0xFF16213E,0xFF2563EB,18),gravity="center_vertical",
        {
          LinearLayout,gravity="center",layout_width="48dp",layout_height="48dp",
          background=grad(0xFF2563EB,0xFF1E40AF,24),
          {TextView,id="tvN",textSize="14sp",textColor=0xFFFFFFFF,typeface=Typeface.DEFAULT_BOLD,gravity="center"}
        },
        {View,layout_width="16dp",layout_height="fill"},
        {TextView,id="tvM",textSize="16sp",textColor=0xFFF1F5F9,typeface=Typeface.DEFAULT_BOLD,layout_width="fill",layout_weight="1"}
      }
    }
    local a = LuaAdapter(activity,dl,il)
    lstS.setAdapter(a)
    lstS.setOnItemClickListener(AdapterView.OnItemClickListener{
      onItemClick=function(p,v,pos,id) vibrate(35) showSurahPopup(ri[pos+1]) end
    })
  end

  loadF("")
  etS.addTextChangedListener({
    onTextChanged=function(s,a,b,c) loadF(tostring(s)) end,
    beforeTextChanged=function(s,a,b,c) end,
    afterTextChanged=function(s) end
  })

  btnSet.onClick=function() showSettings() end
  btnBmMain.onClick=function() showBookmarksDialog(nil) end
  btnAb.onClick=function() showAbout() end
  btnEx.onClick=function() vibrate(40) stopAll() activity.finish() end
end

showMainList()

function onStop()
  if not backgroundAudio then
    pcall(function() stopAll() end)
  end
end

function onDestroy()
  if not backgroundAudio then
    pcall(function() stopAll() end)
  end
end
