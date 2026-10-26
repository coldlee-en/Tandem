#!/usr/bin/env python3
"""Exercise actual patched NCCH/RomFS methods with synthetic ciphertext and keys.
Graphics/CPU and the OS file interface are not exercised. No console data is used.
Requires a C++23 compiler and Crypto++ headers/static library supplied by caller.
"""
from pathlib import Path
import argparse, subprocess, tempfile

def function(source, signature):
    start=source.index(signature)
    end=source.index('\n}',start)+2
    return source[start:end]

def run(root, include, library):
    cpp=(root/'System/core/file_sys/ncch_container.cpp').read_text()
    header=(root/'System/include/core/file_sys/ncch_container.h').read_text()
    rom=(root/'System/core/file_sys/romfs_reader.cpp').read_text()
    arithmetic=(root/'System/core/hw/aes/arithmetic128.cpp').read_text()
    structures=header[header.index('enum NCSDContentIndex'):header.index('namespace FileSys {')]
    cls=header[header.index('class NCCHContainer'):header.index('\n};',header.index('class NCCHContainer'))+3]
    native='\n\n'.join(function(cpp,'Loader::ResultStatus NCCHContainer::'+name) for name in ['LoadHeader()', 'Load()', 'LoadSectionExeFS(', 'ReadRomFS('])
    native+='\n'+function(cpp,'u64 GetModId(')
    # The native Load uses GetModId before its definition.
    native='u64 GetModId(u64);\n'+function(cpp,'static std::size_t LZSS_GetDecompressedSize(')+'\n'+function(cpp,'static bool LZSS_Decompress(')+'\n'+native
    native+='\n'+function(rom,'std::size_t DirectRomFSReader::ReadFile(')
    native+='\n'+function(rom,'std::vector<std::pair<std::size_t, std::size_t>> DirectRomFSReader::BreakupRead(')
    template=Path(__file__).with_name('NCCHCryptoHarness.cpp.in').read_text()
    for name,value in [('ARITHMETIC',arithmetic[arithmetic.index('namespace HW::AES {'):]),('STRUCTURES',structures),('CLASS',cls),('NATIVE',native)]:
        marker='// ACTUAL_'+name
        assert template.count(marker)==1
        template=template.replace(marker,value)
    with tempfile.TemporaryDirectory(prefix='tandem-ncch-test-') as tmp:
        src=Path(tmp)/'test.cpp';src.write_text(template)
        command=['g++','-std=gnu++23','-O1','-g','-fsanitize=address,undefined','-fno-omit-frame-pointer','-I'+str(root/'System/include'),'-I'+str(include),str(src),str(library),'-lpthread','-o',str(Path(tmp)/'test')]
        subprocess.run(command,check=True,timeout=120)
        subprocess.run([str(Path(tmp)/'test')],check=True,timeout=30)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source',type=Path)
    p.add_argument('--cryptopp-include',type=Path,required=True)
    p.add_argument('--cryptopp-library',type=Path,required=True)
    args=p.parse_args()
    run(args.source,args.cryptopp_include,args.cryptopp_library)
