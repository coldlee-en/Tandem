from pathlib import Path
import argparse
import subprocess,tempfile
parser = argparse.ArgumentParser(description='Test the actual core save-state writer against controlled filesystem failures.')
parser.add_argument('source', type=Path)
args = parser.parse_args()
s=(args.source / 'System/core/savestate.cpp').read_text()
header=s[s.index('struct CSTHeader'):s.index('static_assert(sizeof(CSTHeader)')]
method=s[s.index('void System::SaveState(u32 slot) const {'):s.index('void System::LoadState(u32 slot)')]
code=r'''
#include <array>
#include <vector>
#include <string>
#include <span>
#include <sstream>
#include <chrono>
#include <cstring>
#include <cstdio>
#include <stdexcept>
#include <filesystem>
#include <cassert>
using u8=unsigned char;using u32=unsigned;using u64=unsigned long long;using u64_le=u64;using u32_le=u32;
namespace Common {const char* g_scm_rev="abc";const char* g_build_fullname="test";namespace Compression{std::vector<u8> CompressDataZSTDDefault(std::span<const u8> d){return {d.begin(),d.end()};}}}
namespace CryptoPP {struct StringSink{StringSink(std::string& s){s=std::string(20,'x');}};struct HexDecoder{HexDecoder(StringSink* p){delete p;}};struct StringSource{StringSource(const char*,bool,HexDecoder*p){delete p;}};}
namespace FileUtil {
int failure=0;
bool CreateFullPath(const std::string& p){std::filesystem::create_directories(std::filesystem::path(p).parent_path());return true;}
bool Rename(const std::string&a,const std::string&b){return failure!=3 && std::rename(a.c_str(),b.c_str())==0;}
bool Delete(const std::string&p){return std::remove(p.c_str())==0;}
struct IOFile {FILE*f;IOFile(const std::string&p,const char*m):f(std::fopen(p.c_str(),m)){}~IOFile(){if(f)std::fclose(f);}operator bool()const{return f;}size_t WriteBytes(const void*p,size_t n){return failure==1?0:std::fwrite(p,1,n,f);}bool Flush(){return failure!=2 && std::fflush(f)==0;}bool Close(){auto r=std::fclose(f);f=nullptr;return r==0;}};
}
struct oarchive{std::ostream&o;oarchive(std::ostream&s):o(s){}template<class T>void operator&(const T&){o<<"state fixture";}};
namespace Core {
#pragma pack(push, 1)
HEADER
#pragma pack(pop)
constexpr std::array<u8,4> header_magic_bytes{{'C','S','T',0x1b}};
std::string GetSaveStatePath(u64,u64,u32){return "states/test.cst";}
struct Loader{bool SupportsSaveStates(){return true;}};
struct Movie{u64 GetCurrentMovieID()const{return 0;}};
struct System{Loader*app_loader=nullptr;Movie movie;u64 title_id=1;void SaveState(u32)const;};
METHOD
}
std::string bytes(){FILE*f=std::fopen("states/test.cst","rb");std::string s;char b[512];size_t n;while((n=std::fread(b,1,sizeof(b),f)))s.append(b,n);std::fclose(f);return s;}
int main(){Core::System s;s.SaveState(1);auto original=bytes();assert(original.size()>256);for(int failure=1;failure<=3;++failure){FileUtil::failure=failure;bool threw=false;try{s.SaveState(1);}catch(...){threw=true;}assert(threw);assert(bytes()==original);}FileUtil::failure=0;s.SaveState(1);assert(bytes().size()==original.size());}
'''.replace('HEADER',header).replace('METHOD',method)
with tempfile.TemporaryDirectory() as t:
 p=Path(t);(p/'test.cpp').write_text(code)
 subprocess.run(['c++','-std=c++20',str(p/'test.cpp'),'-o',str(p/'test')],check=True,timeout=60)
 subprocess.run([str(p/'test')],cwd=t,check=True,timeout=10)
print('Actual core SaveState writer preserved the old slot after write, flush and rename failures; successful replacement passed.')
