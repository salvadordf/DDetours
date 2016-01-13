// **************************************************************************************************
// CPUID for Delphi.
// Unit CPUID
// https://github.com/MahdiSafsafi/delphi-detours-library

// The contents of this file are subject to the Mozilla Public License Version 1.1 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy of the
// License at http://www.mozilla.org/MPL/
//
// Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF
// ANY KIND, either express or implied. See the License for the specific language governing rights
// and limitations under the License.
//
// The Original Code is CPUID.pas.
//
// The Initial Developer of the Original Code is Mahdi Safsafi [SMP3].
// Portions created by Mahdi Safsafi . are Copyright (C) 2013-2015 Mahdi Safsafi .
// All Rights Reserved.
//
// **************************************************************************************************

unit CPUID;
{$ifdef FPC}
 {$mode Delphi}
{$endif}
interface

{$I Defs.inc}

uses SysUtils;

type
  { Do not change registers order ! }
  TCPUIDStruct = packed record
    rEAX: UInt32; { EAX Register }
    rEBX: UInt32; { EBX Register }
    rEDX: UInt32; { EDX Register }
    rECX: UInt32; { ECX Register }
  end;

  PCPUIDStruct = ^TCPUIDStruct;

procedure CallCPUID(const ID: NativeUInt; var CPUIDStruct: TCPUIDStruct);
function IsCPUIDSupported: Boolean;

type
  TCPUVendor = (vUnknown, vIntel, vAMD, vNextGen);
  TCPUEncoding = set of (REX, VEX, EVEX);
  TCPUInstructions = set of (iMultiNop);

var
  CPUVendor: TCPUVendor;
  CPUEncoding: TCPUEncoding;
  CPUInsts: TCPUInstructions;

implementation

var
  CPUIDSupported: Boolean = False;

function ___IsCPUIDSupported: Boolean;
asm
  {$IFDEF CPUX86}
  PUSH ECX
  PUSHFD
  POP EAX { EAX = EFLAGS }
  MOV ECX, EAX  { Save the original EFLAGS value . }
  {
  CPUID is supported only if we can modify
  bit 21 of EFLAGS register !
   }
  XOR EAX, $200000
  PUSH EAX
  POPFD { Set the new EFLAGS value }
  PUSHFD
  POP EAX { Read EFLAGS }
  {
  Check if the 21 bit was modified !
  If so ==> Return True .
  else  ==> Return False.
   }
  XOR EAX, ECX
  SHR EAX, 21
  AND EAX, 1
  PUSH ECX
  POPFD  { Restore original EFLAGS value . }
  POP ECX
  {$ELSE !CPUX86}
  PUSH RCX
  MOV RCX,RCX
  PUSHFQ
  POP RAX
  MOV RCX, RAX
  XOR RAX, $200000
  PUSH RAX
  POPFQ
  PUSHFQ
  POP RAX
  XOR RAX, RCX
  SHR RAX, 21
  AND RAX, 1
  PUSH RCX
  POPFQ
  POP RCX
  {$ENDIF CPUX86}
end;

procedure ___CallCPUID(const ID: NativeInt; var CPUIDStruct);
asm
  {
  ALL REGISTERS (rDX,rCX,rBX) MUST BE SAVED BEFORE
  EXECUTING CPUID INSTRUCTION !
   }
  {$IFDEF CPUX86}
  PUSH EDI
  PUSH ECX
  PUSH EBX
  MOV EDI,EDX
  CPUID
  MOV EDI.TCPUIDStruct.rEAX,EAX
  MOV EDI.TCPUIDStruct.rEBX,EBX
  MOV EDI.TCPUIDStruct.rECX,ECX
  MOV EDI.TCPUIDStruct.rEDX,EDX
  POP EBX
  POP ECX
  POP EDI
  {$ELSE !CPUX86}
  PUSH R9
  PUSH RBX
  PUSH RDX
  MOV RAX,RCX
  MOV R9,RDX
  CPUID
  MOV R9.TCPUIDStruct.rEAX,EAX
  MOV R9.TCPUIDStruct.rEBX,EBX
  MOV R9.TCPUIDStruct.rECX,ECX
  MOV R9.TCPUIDStruct.rEDX,EDX
  POP RDX
  POP RBX
  POP R9
  {$ENDIF CPUX86}
end;

function ___IsAVXSupported: Boolean;
asm
  {
  Checking for AVX support requires 3 steps:

  1) Detect CPUID.1:ECX.OSXSAVE[bit 27] = 1
  => XGETBV enabled for application use

  2) Detect CPUID.1:ECX.AVX[bit 28] = 1
  => AVX instructions supported.

  3) Issue XGETBV and verify that XCR0[2:1] = �11b�
  => XMM state and YMM state are enabled by OS.

   }

  { Steps : 1 and 2 }
  {$IFDEF CPUX64}
  MOV RAX, 1
  PUSH RCX
  PUSH RBX
  PUSH RDX
  {$ELSE !CPUX64}
  MOV EAX, 1
  PUSH ECX
  PUSH EBX
  PUSH EDX
  {$ENDIF CPUX64}
  CPUID
  AND ECX, $018000000
  CMP  ECX, $018000000
  JNE  @@NOT_SUPPORTED
  XOR  ECX,ECX
  {
  Delphi does not support XGETBV !
  => We need to use the XGETBV opcodes !
   }
  DB $0F DB $01 DB $D0 // XGETBV
  { Step :3 }
  AND EAX, $06
  CMP  EAX, $06
  JNE @@NOT_SUPPORTED
  MOV EAX, 1
  JMP @@END
@@NOT_SUPPORTED:
  XOR EAX,EAX
@@END:
  {$IFDEF CPUX64}
  POP RDX
  POP RBX
  POP RCX
  {$ELSE !CPUX64}
  POP EDX
  POP EBX
  POP ECX
  {$ENDIF CPUX64}
end;

procedure CallCPUID(const ID: NativeUInt; var CPUIDStruct: TCPUIDStruct);
begin
  FillChar(CPUIDStruct, SizeOf(TCPUIDStruct), #0);
  if not CPUIDSupported then
    raise Exception.Create('CPUID instruction not supported.')
  else
    ___CallCPUID(ID, CPUIDStruct);
end;

function IsCPUIDSupported: Boolean;
begin
  Result := CPUIDSupported;
end;

type
  TVendorName = array [0 .. 12] of AnsiChar;

function GetVendorName: TVendorName;
var
  Info: PCPUIDStruct;
  P: PByte;
begin
  Result := '';
  if not IsCPUIDSupported then
    Exit;
  Info := GetMemory(SizeOf(TCPUIDStruct));
  CallCPUID(0, Info^);
  P := PByte(Info) + 4; // Skip EAX !
  Move(P^, PByte(@Result[0])^, 12);
  FreeMemory(Info);
end;

procedure __Init__;
var
  vn: TVendorName;
  Info: TCPUIDStruct;
  r: UInt32;
begin
  CPUVendor := vUnknown;
{$IFDEF CPUX64}
  CPUEncoding := [REX];
{$ELSE !CPUX64}
  CPUEncoding := [];
{$ENDIF CPUX64}
  CPUInsts := [];
  if IsCPUIDSupported then
  begin
    vn := GetVendorName();
    if vn = 'GenuineIntel' then
      CPUVendor := vIntel
    else if vn = 'AuthenticAMD' then
      CPUVendor := vAMD
    else if vn = 'NexGenDriven' then
      CPUVendor := vNextGen;
    CallCPUID(1, Info);
    r := Info.rEAX and $F00;
    case r of
      $F00, $600:
        Include(CPUInsts, iMultiNop);
    end;
    if ___IsAVXSupported then
      Include(CPUEncoding, VEX);
  end;
end;

initialization

CPUIDSupported := ___IsCPUIDSupported;
__Init__;

end.
