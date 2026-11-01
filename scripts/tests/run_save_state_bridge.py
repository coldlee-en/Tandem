#!/usr/bin/env python3
"""Compile the actual patched bridge methods against deterministic core stubs."""
from pathlib import Path
import argparse
import subprocess
import tempfile
p = argparse.ArgumentParser()
p.add_argument('source', type=Path)
a = p.parse_args()
bridge = (a.source / 'System/bridge.cpp').read_text()
start = bridge.index('namespace {\nstd::mutex state_mutex;')
end = bridge.index('void cytrus::set_screens(', start)
methods = bridge[start:end]
code = r'''
#include <atomic>
#include <thread>
#include <future>
#include <functional>
#include <vector>
#include <mutex>
#include <chrono>
#include <string>
#include <cassert>
#include <stdexcept>
using u64 = unsigned long long; using u32 = unsigned;
namespace Loader { enum class ResultStatus { Success }; }
namespace Core {
struct SaveStateInfo { u32 slot; u64 time; enum class ValidationStatus { OK, BuildMismatch }; ValidationStatus status; };
inline std::vector<SaveStateInfo> ListSaveStates(u64, u64) { return {{1, 123, SaveStateInfo::ValidationStatus::OK}}; }
inline SaveStateInfo GetSaveStateInfo(u64,u64,u32 slot) { return {slot,123,slot==1?SaveStateInfo::ValidationStatus::OK:SaveStateInfo::ValidationStatus::BuildMismatch}; }
struct FakeLoader { Loader::ResultStatus ReadProgramId(u64& id) { id=1;return Loader::ResultStatus::Success; } };
struct FakeMovie { u64 GetCurrentMovieID() { return 0; } };
struct FakeKernel { bool pending=false; bool AreAsyncOperationsPending() {return pending;} };
struct System {
 enum class ResultStatus { Success };
 std::atomic<bool> tick{false}; std::thread::id worker; FakeLoader loader; FakeMovie movie; FakeKernel kernel; bool fail=false; int saves=0,loads=0;
 static System& GetInstance(){static System s;return s;}
 bool IsPoweredOn(){return true;}
 FakeLoader& GetAppLoader(){return loader;} FakeMovie& Movie(){return movie;} FakeKernel& Kernel(){return kernel;}
 void SaveState(int){assert(std::this_thread::get_id()==worker);if(fail)throw std::runtime_error("disk full");++saves;}
 void LoadState(int){assert(std::this_thread::get_id()==worker);++loads;}
 ResultStatus RunLoop(){worker=std::this_thread::get_id();tick=true;std::this_thread::yield();return ResultStatus::Success;}
 void Shutdown(){}
}; }
struct {std::jthread thread;std::atomic<bool> running{false},paused{false};}cntnr;
namespace InputManager {void Shutdown(){}}
namespace Network {void Shutdown(){}}
namespace cytrus {std::string state_action(int,int);void start();void stop();}
METHODS
int main(){
 auto& s=Core::System::GetInstance();
 assert(cytrus::state_action(0,0).find("ended")!=std::string::npos);
 cntnr.running=true;cytrus::start();
 // Wait until the core has executed at least one tick before checking worker affinity.
 while(!s.tick.load())std::this_thread::yield();
 cntnr.paused=true;
 assert(cytrus::state_action(0,0)=="OK\n1|123|1\n");
 assert(cytrus::state_action(1,1)=="OK\n");
 assert(s.saves==1);
 assert(cytrus::state_action(2,1)=="OK\n");
 assert(s.loads==1);
 assert(cytrus::state_action(2,2).find("incompatible")!=std::string::npos);
 s.kernel.pending=true;assert(cytrus::state_action(1,1).find("busy")!=std::string::npos);s.kernel.pending=false;
 s.fail=true;assert(cytrus::state_action(1,1)=="disk full");s.fail=false;
 assert(cytrus::state_action(1,9).find("Invalid")!=std::string::npos);
 assert(cytrus::state_action(1,1)=="OK\n");
 cytrus::stop();
 assert(cytrus::state_action(0,0).find("ended")!=std::string::npos);
}
'''.replace('METHODS', methods)
with tempfile.TemporaryDirectory() as tmp:
    f = Path(tmp)
    (f/'test.cpp').write_text(code)
    subprocess.run(['c++', '-std=c++20', '-pthread', str(f/'test.cpp'), '-o', str(f/'test')], check=True, timeout=60)
    subprocess.run([str(f/'test')], check=True, timeout=30)
print('Save-state bridge: worker-thread execution, paused operation, invalid/missing slots, busy core, write errors and stopped sessions passed')
