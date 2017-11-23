module llvm.config;

import std.conv : to;
import std.array : array, replace, join;
import std.algorithm.iteration : filter, map, joiner;
import std.algorithm.searching : canFind;

/// LLVM Versions that llvm-d supports
immutable LLVM_Versions = [
	[4,0,0],
	[3,9,1],
	[3,9,0],
	[3,8,1],
	[3,8,0],
	[3,7,1],
	[3,7,0],
	[3,6,2],
	[3,6,1],
	[3,6,0],
	[3,5,2],
	[3,5,1],
	[3,5,0],
	[3,4,2],
	[3,4,1],
	[3,4,0],
	[3,3,0],
	[3,2,0],
	[3,1,0],
];

mixin(LLVM_Versions.map!(ver =>
	q{version(LLVM_%MAJOR_%MINOR_%PATCH) {
			immutable LLVM_VERSION_MAJOR = %MAJOR;
			immutable LLVM_VERSION_MINOR = %MINOR;
			immutable LLVM_VERSION_PATCH = %PATCH;
		}}.replace("%MAJOR", ver[0].to!string).replace("%MINOR", ver[1].to!string).replace("%PATCH", ver[2].to!string)
	).join("else\n") ~
	q{else {
		immutable LLVM_VERSION_MAJOR = LLVM_Versions[0][0];
		immutable LLVM_VERSION_MINOR = LLVM_Versions[0][1];
		immutable LLVM_VERSION_PATCH = LLVM_Versions[0][2];
	}}
);

/// Makes an ordered identifier from a major, minor, and patch number
pure nothrow @nogc
ulong asVersion(ushort major, ushort minor, ushort patch)
{
	return cast(ulong)(major) << (ushort.sizeof*2*8) | cast(ulong)(minor) << (ushort.sizeof*8) | cast(ulong)(patch);
}

/// LLVM Version that llvm-d was compiled against
immutable LLVM_Version = asVersion(LLVM_VERSION_MAJOR, LLVM_VERSION_MINOR, LLVM_VERSION_PATCH);

/// LLVM Targets that can be used (enable target Name via version LLVM_Target_Name)
immutable LLVM_Targets = {
	string[] targets;
	mixin({
			static if (LLVM_Version >= asVersion(4, 0, 0)) {
				return ["AArch64","AMDGPU","ARM","AVR","BPF","Hexagon","Lanai","MSP430","Mips","NVPTX","PowerPC","RISCV","Sparc","SystemZ","WebAssembly","X86","XCore"];
			} else static if (LLVM_Version >= asVersion(3, 9, 0)) {
				return ["AArch64","AMDGPU","ARM","AVR","BPF","Hexagon","Lanai","MSP430","Mips","NVPTX","PowerPC","Sparc","SystemZ","WebAssembly","X86","XCore"];
			} else static if (LLVM_Version >= asVersion(3, 8, 0)) {
				return ["AArch64","AMDGPU","ARM","AVR","BPF","CppBackend","Hexagon","MSP430","Mips","NVPTX","PowerPC","Sparc","SystemZ","WebAssembly","X86","XCore"];
			} else static if (LLVM_Version >= asVersion(3, 7, 0)) {
				return ["AArch64","AMDGPU","ARM","BPF","CppBackend","Hexagon","MSP430","Mips","NVPTX","PowerPC","Sparc","SystemZ","WebAssembly","X86","XCore"];
			} else static if (LLVM_Version >= asVersion(3, 6, 0)) {
				return ["AArch64","ARM","CppBackend","Hexagon","MSP430","Mips","NVPTX","PowerPC","R600","Sparc","SystemZ","X86","XCore"];
			} else static if (LLVM_Version >= asVersion(3, 5, 0)) {
				return ["AArch64","ARM","CppBackend","Hexagon","MSP430","Mips","NVPTX","PowerPC","R600","Sparc","SystemZ","X86","XCore"];
			} else static if (LLVM_Version >= asVersion(3, 4, 0)) {
				return ["AArch64","ARM","CppBackend","Hexagon","MSP430","Mips","NVPTX","PowerPC","R600","Sparc","SystemZ","X86","XCore"];
			} else static if (LLVM_Version >= asVersion(3, 3, 0)) {
				return ["AArch64","ARM","CppBackend","Hexagon","MBlaze","MSP430","Mips","NVPTX","PowerPC","R600","Sparc","SystemZ","X86","XCore"];
			} else static if (LLVM_Version >= asVersion(3, 2, 0)) {
				return ["ARM","CellSPU","CppBackend","Hexagon","MBlaze","MSP430","Mips","NVPTX","PTX","PowerPC","Sparc","X86","XCore"];
			} else {
				return ["ARM","CellSPU","CppBackend","Hexagon","MBlaze","MSP430","Mips","PTX","PowerPC","Sparc","X86","XCore"];
			}
		}().map!(t => "version (LLVM_Target_" ~ t ~ ") targets ~= \"" ~ t ~ "\";").joiner.array);
	return targets;
}();

/// LLVM Targets with AsmPrinter capability (if enabled)
immutable LLVM_AsmPrinters = {
	static if (LLVM_Version >= asVersion(4, 0, 0)) {
		return ["AArch64","AMDGPU","ARM","AVR","BPF","Hexagon","Lanai","MSP430","Mips","NVPTX","PowerPC","Sparc","SystemZ","WebAssembly","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 9, 0)) {
		return ["AArch64","AMDGPU","ARM","BPF","Hexagon","Lanai","MSP430","Mips","NVPTX","PowerPC","Sparc","SystemZ","WebAssembly","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 8, 0)) {
		return ["AArch64","AMDGPU","ARM","BPF","Hexagon","MSP430","Mips","NVPTX","PowerPC","Sparc","SystemZ","WebAssembly","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 7, 0)) {
		return ["AArch64","AMDGPU","ARM","BPF","Hexagon","MSP430","Mips","NVPTX","PowerPC","Sparc","SystemZ","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 6, 0)) {
		return ["AArch64","ARM","Hexagon","MSP430","Mips","NVPTX","PowerPC","R600","Sparc","SystemZ","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 5, 0)) {
		return ["AArch64","ARM","Hexagon","MSP430","Mips","NVPTX","PowerPC","R600","Sparc","SystemZ","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 4, 0)) {
		return ["AArch64","ARM","Hexagon","MSP430","Mips","NVPTX","PowerPC","R600","Sparc","SystemZ","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 3, 0)) {
		return ["AArch64","ARM","Hexagon","MBlaze","MSP430","Mips","NVPTX","PowerPC","R600","Sparc","SystemZ","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 2, 0)) {
		return ["ARM","CellSPU","Hexagon","MBlaze","MSP430","Mips","NVPTX","PowerPC","Sparc","X86","XCore"];
	} else {
		return ["ARM","CellSPU","Hexagon","MBlaze","MSP430","Mips","PTX","PowerPC","Sparc","X86","XCore"];
	}
}().filter!(t => LLVM_Targets.canFind(t)).array;

/// LLVM Targets with AsmParser capability (if enabled)
immutable LLVM_AsmParsers = {
	static if (LLVM_Version >= asVersion(4, 0, 0)) {
		return ["AArch64","AMDGPU","ARM","AVR","Hexagon","Lanai","Mips","PowerPC","Sparc","SystemZ","X86"];
	} else static if (LLVM_Version >= asVersion(3, 9, 0)) {
		return ["AArch64","AMDGPU","ARM","Hexagon","Lanai","Mips","PowerPC","Sparc","SystemZ","X86"];
	} else static if (LLVM_Version >= asVersion(3, 8, 0)) {
		return ["AArch64","AMDGPU","ARM","Hexagon","Mips","PowerPC","Sparc","SystemZ","X86"];
	} else static if (LLVM_Version >= asVersion(3, 7, 0)) {
		return ["AArch64","AMDGPU","ARM","Mips","PowerPC","Sparc","SystemZ","X86"];
	} else static if (LLVM_Version >= asVersion(3, 6, 0)) {
		return ["AArch64","ARM","Mips","PowerPC","R600","Sparc","SystemZ","X86"];
	} else static if (LLVM_Version >= asVersion(3, 5, 0)) {
		return ["AArch64","ARM","Mips","PowerPC","Sparc","SystemZ","X86"];
	} else static if (LLVM_Version >= asVersion(3, 4, 0)) {
		return ["AArch64","ARM","Mips","PowerPC","SystemZ","X86"];
	} else static if (LLVM_Version >= asVersion(3, 3, 0)) {
		return ["AArch64","ARM","MBlaze","Mips","PowerPC","SystemZ","X86"];
	} else static if (LLVM_Version >= asVersion(3, 2, 0)) {
		return ["ARM","MBlaze","Mips","X86"];
	} else {
		return ["ARM","MBlaze","Mips","X86"];
	}
}().filter!(t => LLVM_Targets.canFind(t)).array;

/// LLVM Targets with Disassembler capability (if enabled)
immutable LLVM_Disassemblers = {
	static if (LLVM_Version >= asVersion(4, 0, 0)) {
		return ["AArch64","AMDGPU","ARM","AVR","BPF","Hexagon","Lanai","Mips","PowerPC","Sparc","SystemZ","WebAssembly","X86","XCore"];
	} else  static if (LLVM_Version >= asVersion(3, 9, 0)) {
		return ["AArch64","AMDGPU","ARM","Hexagon","Lanai","Mips","PowerPC","Sparc","SystemZ","WebAssembly","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 8, 0)) {
		return ["AArch64","ARM","Hexagon","Mips","PowerPC","Sparc","SystemZ","WebAssembly","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 7, 0)) {
		return ["AArch64","ARM","Hexagon","Mips","PowerPC","Sparc","SystemZ","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 6, 0)) {
		return ["AArch64","ARM","Hexagon","Mips","PowerPC","Sparc","SystemZ","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 5, 0)) {
		return ["AArch64","ARM","Mips","PowerPC","Sparc","SystemZ","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 4, 0)) {
		return ["AArch64","ARM","Mips","SystemZ","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 3, 0)) {
		return ["AArch64","ARM","MBlaze","Mips","X86","XCore"];
	} else static if (LLVM_Version >= asVersion(3, 2, 0)) {
		return ["ARM","MBlaze","Mips","X86"];
	} else {
		return ["ARM","MBlaze","Mips","X86"];
	}
}().filter!(t => LLVM_Targets.canFind(t)).array;

/// LLVM Target that corresponds to the native architecture (if enabled)
immutable LLVM_NativeTarget = {
	auto t = {
		     version(X86)     return "X86";
		else version(X86_64)  return "X86";
		else version(SPARC)   return "Sparc";
		else version(SPARC64) return "Sparc";
		else version(PPC)     return "PowerPC";
		else version(PPC64)   return "PowerPC";
		else version(AArch64) return "AArch64";
		else version(ARM)     return "ARM";
		else version(MIPS32)  return "Mips";
		else version(MIPS64)  return "Mips";
		else version(SystemZ) return "SystemZ";
		else                  return "";
	}();
	if (t != "" && LLVM_Targets.canFind(t)) return t;
	else return "";
}();