# rtmr1.py
import pefile, hashlib, sys

def authenticode(path, algo="sha384"):
    pe = pefile.PE(path); data = pe.__data__; h = hashlib.new(algo)
    ck = pe.OPTIONAL_HEADER.get_file_offset() + 64
    sec = pe.OPTIONAL_HEADER.DATA_DIRECTORY[4]
    cdir, cva, csize = sec.get_file_offset(), sec.VirtualAddress, sec.Size
    soh = pe.OPTIONAL_HEADER.SizeOfHeaders
    h.update(data[0:ck]); h.update(data[ck+4:cdir]); h.update(data[cdir+8:soh])
    summed = soh
    for s in sorted(pe.sections, key=lambda x: x.PointerToRawData):
        n = s.SizeOfRawData
        if n:
            h.update(data[s.PointerToRawData:s.PointerToRawData+n]); summed += n
    if len(data) > summed:
        end = cva if (csize and cva) else len(data)
        h.update(data[summed:end])
    return h.digest()

rtmr = b"\x00" * 48
for name, path in [("shim", sys.argv[1]), ("grub", sys.argv[2]), ("kernel", sys.argv[3])]:
    d = authenticode(path)
    print(f"{name:6s} {d.hex()}")
    rtmr = hashlib.sha384(rtmr + d).digest()     # RTMR extend: SHA384(prev ‖ digest)
print("RTMR1 =", rtmr.hex())
