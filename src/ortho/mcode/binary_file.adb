--  Binary file handling.
--  Copyright (C) 2006 Tristan Gingold
--
--  GHDL is free software; you can redistribute it and/or modify it under
--  the terms of the GNU General Public License as published by the Free
--  Software Foundation; either version 2, or (at your option) any later
--  version.
--
--  GHDL is distributed in the hope that it will be useful, but WITHOUT ANY
--  WARRANTY; without even the implied warranty of MERCHANTABILITY or
--  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
--  for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with GCC; see the file COPYING.  If not, write to the Free
--  Software Foundation, 59 Temple Place - Suite 330, Boston, MA
--  02111-1307, USA.
with System.Storage_Elements;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Characters.Latin_1;
with Ada.Unchecked_Conversion;
with Hex_Images; use Hex_Images;
with Disassemble;

package body Binary_File is
   Cur_Sect : Section_Acc := null;

   HT : Character renames Ada.Characters.Latin_1.HT;

   function To_Byte_Array_Acc is new Ada.Unchecked_Conversion
     (Source => System.Address, Target => Byte_Array_Acc);

   --  Resize a section to SIZE bytes.
   procedure Resize (Sect : Section_Acc; Size : Pc_Type) is
   begin
      Sect.Data_Max := Size;
      Memsegs.Resize (Sect.Seg, Natural (Size));
      Sect.Data := To_Byte_Array_Acc (Memsegs.Get_Address (Sect.Seg));
   end Resize;

   function Get_Scope (Sym : Symbol) return Symbol_Scope is
   begin
      return Symbols.Table (Sym).Scope;
   end Get_Scope;

   procedure Set_Scope (Sym : Symbol; Scope : Symbol_Scope) is
   begin
      Symbols.Table (Sym).Scope := Scope;
   end Set_Scope;

   function Get_Section (Sym : Symbol) return Section_Acc is
   begin
      return Symbols.Table (Sym).Section;
   end Get_Section;

   procedure Set_Section (Sym : Symbol; Sect : Section_Acc) is
   begin
      Symbols.Table (Sym).Section := Sect;
   end Set_Section;

   function Get_Number (Sym : Symbol) return Natural is
   begin
      return Symbols.Table (Sym).Number;
   end Get_Number;

   procedure Set_Number (Sym : Symbol; Num : Natural) is
   begin
      Symbols.Table (Sym).Number := Num;
   end Set_Number;

   function Get_Relocs (Sym : Symbol) return Reloc_Acc is
   begin
      return Symbols.Table (Sym).Relocs;
   end Get_Relocs;

   procedure Set_Relocs (Sym : Symbol; Reloc : Reloc_Acc) is
   begin
      Symbols.Table (Sym).Relocs := Reloc;
   end Set_Relocs;

   function Get_Name (Sym : Symbol) return O_Ident is
   begin
      return Symbols.Table (Sym).Name;
   end Get_Name;

   function Get_Used (Sym : Symbol) return Boolean is
   begin
      return Symbols.Table (Sym).Used;
   end Get_Used;

   procedure Set_Used (Sym : Symbol; Val : Boolean) is
   begin
      Symbols.Table (Sym).Used := Val;
   end Set_Used;

   function Get_Symbol_Value (Sym : Symbol) return Pc_Type is
   begin
      return Symbols.Table (Sym).Value;
   end Get_Symbol_Value;

   procedure Set_Symbol_Value (Sym : Symbol; Val : Pc_Type) is
   begin
      Symbols.Table (Sym).Value := Val;
   end Set_Symbol_Value;

   function S_Defined (Sym : Symbol) return Boolean is
   begin
      return Get_Scope (Sym) /= Sym_Undef;
   end S_Defined;
   pragma Unreferenced (S_Defined);

   function S_Local (Sym : Symbol) return Boolean is
   begin
      return Get_Scope (Sym) = Sym_Local;
   end S_Local;

   procedure Create_Section (Sect : out Section_Acc;
                             Name : String; Flags : Section_Flags)
   is
   begin
      Sect := new Section_Type'(Next => null,
                                Flags => Flags,
                                Name => new String'(Name),
                                Link => null,
                                Align => 2,
                                Esize => 0,
                                Pc => 0,
                                Insn_Pc => 0,
                                Data => null,
                                Data_Max => 0,
                                First_Reloc => null,
                                Last_Reloc => null,
                                Nbr_Relocs => 0,
                                Number => 0,
                                Seg => Memsegs.Create,
                                Vaddr => 0);
      if (Flags and Section_Zero) = 0 then
         --  Allocate memory for the segment, unless BSS.
         Resize (Sect, 8192);
      end if;
      if (Flags and Section_Strtab) /= 0 then
         Sect.Align := 0;
      end if;
      if Section_Chain = null then
         Section_Chain := Sect;
      else
         Section_Last.Next := Sect;
      end if;
      Section_Last := Sect;
      Nbr_Sections := Nbr_Sections + 1;
   end Create_Section;

   procedure Sect_Prealloc (Sect : Section_Acc; L : Pc_Type)
   is
      New_Max : Pc_Type;
   begin
      if Sect.Pc + L < Sect.Data_Max then
         return;
      end if;
      New_Max := Sect.Data_Max;
      loop
         New_Max := New_Max * 2;
         exit when Sect.Pc + L < New_Max;
      end loop;
      Resize (Sect, New_Max);
   end Sect_Prealloc;

   procedure Merge_Section (Dest : Section_Acc; Src : Section_Acc)
   is
      Rel : Reloc_Acc;
   begin
      --  Sanity checks.
      if Src = null or else Dest = Src then
         raise Program_Error;
      end if;

      Rel := Src.First_Reloc;

      if Rel /= null then
         --  Move relocs.
         if Dest.Last_Reloc = null then
            Dest.First_Reloc := Rel;
            Dest.Last_Reloc := Rel;
         else
            Dest.Last_Reloc.Sect_Next := Rel;
            Dest.Last_Reloc := Rel;
         end if;
         Dest.Nbr_Relocs := Dest.Nbr_Relocs + Src.Nbr_Relocs;


         --  Reloc reloc, since the pc has changed.
         while Rel /= null loop
            Rel.Addr := Rel.Addr + Dest.Pc;
            Rel := Rel.Sect_Next;
         end loop;
      end if;

      if Src.Pc > 0 then
         Sect_Prealloc (Dest, Src.Pc);
         Dest.Data (Dest.Pc .. Dest.Pc + Src.Pc - 1) :=
           Src.Data (0 .. Src.Pc - 1);
         Dest.Pc := Dest.Pc + Src.Pc;
      end if;

      Memsegs.Delete (Src.Seg);
      Src.Pc := 0;
      Src.Data_Max := 0;
      Src.Data := null;
      Src.First_Reloc := null;
      Src.Last_Reloc := null;
      Src.Nbr_Relocs := 0;

      --  Remove from section_chain.
      if Section_Chain = Src then
         Section_Chain := Src.Next;
      else
         declare
            Sect : Section_Acc;
         begin
            Sect := Section_Chain;
            while Sect.Next /= Src loop
               Sect := Sect.Next;
            end loop;
            Sect.Next := Src.Next;
            if Section_Last = Src then
               Section_Last := Sect;
            end if;
         end;
      end if;
      Nbr_Sections := Nbr_Sections - 1;
   end Merge_Section;

   procedure Set_Section_Info (Sect : Section_Acc;
                               Link : Section_Acc;
                               Align : Natural;
                               Esize : Natural)
   is
   begin
      Sect.Link := Link;
      Sect.Align := Align;
      Sect.Esize := Esize;
   end Set_Section_Info;

   procedure Set_Current_Section (Sect : Section_Acc) is
   begin
      --  If the current section does not change, this is a no-op.
      if Cur_Sect = Sect then
         return;
      end if;

      if Dump_Asm then
         Put_Line (HT & ".section """ & Sect.Name.all & """");
      end if;
      Cur_Sect := Sect;
   end Set_Current_Section;

   function Get_Current_Pc return Pc_Type is
   begin
      return Cur_Sect.Pc;
   end Get_Current_Pc;

   function Get_Pc (Sect : Section_Acc) return Pc_Type is
   begin
      return Sect.Pc;
   end Get_Pc;


   procedure Prealloc (L : Pc_Type) is
   begin
      Sect_Prealloc (Cur_Sect, L);
   end Prealloc;

   procedure Start_Insn is
   begin
      --  Check there is enough memory for the next instruction.
      Sect_Prealloc (Cur_Sect, 16);
      if Cur_Sect.Insn_Pc /= 0 then
         --  end_insn was not called.
         raise Program_Error;
      end if;
      Cur_Sect.Insn_Pc := Cur_Sect.Pc;
   end Start_Insn;

   procedure Get_Symbol_At_Addr (Addr : System.Address;
                                 Line : in out String;
                                 Line_Len : in out Natural)
   is
      use System;
      use System.Storage_Elements;
      Off : Pc_Type;
      Reloc : Reloc_Acc;
   begin
      --  Check if addr is in the current section.
      if Addr < Cur_Sect.Data (0)'Address
        or else Addr > Cur_Sect.Data (Cur_Sect.Pc)'Address
      then
         raise Program_Error;
         --return;
      end if;
      Off := Pc_Type
        (To_Integer (Addr) - To_Integer (Cur_Sect.Data (0)'Address));

      --  Find a relocation at OFF.
      Reloc := Cur_Sect.First_Reloc;
      while Reloc /= null loop
         if Reloc.Addr = Off then
            declare
               Str : constant String := Get_Symbol_Name (Reloc.Sym);
            begin
               Line (Line'First .. Line'First + Str'Length - 1) := Str;
               Line_Len := Line_Len + Str'Length;
               return;
            end;
         end if;
         Reloc := Reloc.Sect_Next;
      end loop;
   end Get_Symbol_At_Addr;

   procedure End_Insn
   is
      Str : String (1 .. 256);
      Len : Natural;
      Insn_Len : Natural;
   begin
      --if Insn_Pc = 0 then
      --   --  start_insn was not called.
      --   raise Program_Error;
      --end if;
      if Debug_Hex then
         Put (HT);
         Put ('#');
         for I in Cur_Sect.Insn_Pc .. Cur_Sect.Pc - 1 loop
            Put (' ');
            Put (Hex_Image (Unsigned_8 (Cur_Sect.Data (I))));
         end loop;
         New_Line;
      end if;

      if Dump_Asm then
         Disassemble.Disassemble_Insn
           (Cur_Sect.Data (Cur_Sect.Insn_Pc)'Address,
            Unsigned_32 (Cur_Sect.Insn_Pc),
            Str, Len, Insn_Len,
            Get_Symbol_At_Addr'Access);
         Put (HT);
         Put_Line (Str (1 .. Len));
      end if;
      --if Natural (Cur_Pc - Insn_Pc) /= Insn_Len then
      --   raise Program_Error;
      --end if;
      Cur_Sect.Insn_Pc := 0;
   end End_Insn;

   procedure Gen_B8 (B : Byte) is
   begin
      Cur_Sect.Data (Cur_Sect.Pc) := B;
      Cur_Sect.Pc := Cur_Sect.Pc + 1;
   end Gen_B8;

   procedure Gen_B16 (B0, B1 : Byte) is
   begin
      Cur_Sect.Data (Cur_Sect.Pc + 0) := B0;
      Cur_Sect.Data (Cur_Sect.Pc + 1) := B1;
      Cur_Sect.Pc := Cur_Sect.Pc + 2;
   end Gen_B16;

   procedure Gen_Le8 (B : Unsigned_32) is
   begin
      Cur_Sect.Data (Cur_Sect.Pc) := Byte (B and 16#Ff#);
      Cur_Sect.Pc := Cur_Sect.Pc + 1;
   end Gen_Le8;

   procedure Gen_Le16 (B : Unsigned_32) is
   begin
      Cur_Sect.Data (Cur_Sect.Pc + 0) := Byte (Shift_Right (B, 0) and 16#Ff#);
      Cur_Sect.Data (Cur_Sect.Pc + 1) := Byte (Shift_Right (B, 8) and 16#Ff#);
      Cur_Sect.Pc := Cur_Sect.Pc + 2;
   end Gen_Le16;

   procedure Gen_Be16 (B : Unsigned_32) is
   begin
      Cur_Sect.Data (Cur_Sect.Pc + 0) := Byte (Shift_Right (B, 8) and 16#Ff#);
      Cur_Sect.Data (Cur_Sect.Pc + 1) := Byte (Shift_Right (B, 0) and 16#Ff#);
      Cur_Sect.Pc := Cur_Sect.Pc + 2;
   end Gen_Be16;

   procedure Write_B8 (Sect : Section_Acc; Pc : Pc_Type; V : Unsigned_8) is
   begin
      Sect.Data (Pc) := Byte (V);
   end Write_B8;

   procedure Write_Be16 (Sect : Section_Acc; Pc : Pc_Type; V : Unsigned_32) is
   begin
      Sect.Data (Pc + 0) := Byte (Shift_Right (V, 8) and 16#Ff#);
      Sect.Data (Pc + 1) := Byte (Shift_Right (V, 0) and 16#Ff#);
   end Write_Be16;

   procedure Write_Le32 (Sect : Section_Acc; Pc : Pc_Type; V : Unsigned_32) is
   begin
      Sect.Data (Pc + 0) := Byte (Shift_Right (V, 0) and 16#Ff#);
      Sect.Data (Pc + 1) := Byte (Shift_Right (V, 8) and 16#Ff#);
      Sect.Data (Pc + 2) := Byte (Shift_Right (V, 16) and 16#Ff#);
      Sect.Data (Pc + 3) := Byte (Shift_Right (V, 24) and 16#Ff#);
   end Write_Le32;

   procedure Write_Be32 (Sect : Section_Acc; Pc : Pc_Type; V : Unsigned_32) is
   begin
      Sect.Data (Pc + 0) := Byte (Shift_Right (V, 24) and 16#Ff#);
      Sect.Data (Pc + 1) := Byte (Shift_Right (V, 16) and 16#Ff#);
      Sect.Data (Pc + 2) := Byte (Shift_Right (V, 8) and 16#Ff#);
      Sect.Data (Pc + 3) := Byte (Shift_Right (V, 0) and 16#Ff#);
   end Write_Be32;

   procedure Write_16 (Sect : Section_Acc; Pc : Pc_Type; B : Unsigned_32)
   is
      subtype B2 is Byte_Array_Base (0 .. 1);
      function To_B2 is new Ada.Unchecked_Conversion
        (Source => Unsigned_16, Target => B2);
   begin
      Sect.Data (Pc + 0 .. Pc + 1) := To_B2 (Unsigned_16 (B));
   end Write_16;

   procedure Write_32 (Sect : Section_Acc; Pc : Pc_Type; B : Unsigned_32)
   is
      subtype B4 is Byte_Array_Base (0 .. 3);
      function To_B4 is new Ada.Unchecked_Conversion
        (Source => Unsigned_32, Target => B4);
   begin
      Sect.Data (Pc + 0 .. Pc + 3) := To_B4 (B);
   end Write_32;

   procedure Gen_16 (B : Unsigned_32) is
   begin
      Write_16 (Cur_Sect, Cur_Sect.Pc, B);
      Cur_Sect.Pc := Cur_Sect.Pc + 2;
   end Gen_16;

   procedure Gen_32 (B : Unsigned_32) is
   begin
      Write_32 (Cur_Sect, Cur_Sect.Pc, B);
      Cur_Sect.Pc := Cur_Sect.Pc + 4;
   end Gen_32;

   function Read_Le32 (Sect : Section_Acc; Pc : Pc_Type) return Unsigned_32 is
   begin
      return Shift_Left (Unsigned_32 (Sect.Data (Pc + 0)), 0)
        or Shift_Left (Unsigned_32 (Sect.Data (Pc + 1)), 8)
        or Shift_Left (Unsigned_32 (Sect.Data (Pc + 2)), 16)
        or Shift_Left (Unsigned_32 (Sect.Data (Pc + 3)), 24);
   end Read_Le32;

   function Read_Be32 (Sect : Section_Acc; Pc : Pc_Type) return Unsigned_32 is
   begin
      return Shift_Left (Unsigned_32 (Sect.Data (Pc + 0)), 24)
        or Shift_Left (Unsigned_32 (Sect.Data (Pc + 1)), 16)
        or Shift_Left (Unsigned_32 (Sect.Data (Pc + 2)), 8)
        or Shift_Left (Unsigned_32 (Sect.Data (Pc + 3)), 0);
   end Read_Be32;

   procedure Add_Le32 (Sect : Section_Acc; Pc : Pc_Type; V : Unsigned_32) is
   begin
      Write_Le32 (Sect, Pc, V + Read_Le32 (Sect, Pc));
   end Add_Le32;

   procedure Patch_Le32 (Pc : Pc_Type; V : Unsigned_32) is
   begin
      if Pc + 4 > Get_Current_Pc then
         raise Program_Error;
      end if;
      Write_Le32 (Cur_Sect, Pc, V);
   end Patch_Le32;

   procedure Patch_Be32 (Pc : Pc_Type; V : Unsigned_32) is
   begin
      if Pc + 4 > Get_Current_Pc then
         raise Program_Error;
      end if;
      Write_Be32 (Cur_Sect, Pc, V);
   end Patch_Be32;

   procedure Patch_Be16 (Pc : Pc_Type; V : Unsigned_32) is
   begin
      if Pc + 2 > Get_Current_Pc then
         raise Program_Error;
      end if;
      Write_Be16 (Cur_Sect, Pc, V);
   end Patch_Be16;

   procedure Patch_B8 (Pc : Pc_Type; V : Unsigned_8) is
   begin
      if Pc >= Get_Current_Pc then
         raise Program_Error;
      end if;
      Write_B8 (Cur_Sect, Pc, V);
   end Patch_B8;

   procedure Patch_32 (Pc : Pc_Type; V : Unsigned_32) is
   begin
      if Pc + 4 > Get_Current_Pc then
         raise Program_Error;
      end if;
      Write_32 (Cur_Sect, Pc, V);
   end Patch_32;

   procedure Gen_Le32 (B : Unsigned_32) is
   begin
      Write_Le32 (Cur_Sect, Cur_Sect.Pc, B);
      Cur_Sect.Pc := Cur_Sect.Pc + 4;
   end Gen_Le32;

   procedure Gen_Be32 (B : Unsigned_32) is
   begin
      Write_Be32 (Cur_Sect, Cur_Sect.Pc, B);
      Cur_Sect.Pc := Cur_Sect.Pc + 4;
   end Gen_Be32;

   procedure Gen_Data_Le8 (B : Unsigned_32) is
   begin
      if Dump_Asm then
         Put_Line (HT & ".byte 0x" & Hex_Image (Unsigned_8 (B)));
      end if;
      Gen_Le8 (B);
   end Gen_Data_Le8;

   procedure Gen_Data_Le16 (B : Unsigned_32) is
   begin
      if Dump_Asm then
         Put_Line (HT & ".half 0x" & Hex_Image (Unsigned_16 (B)));
      end if;
      Gen_Le16 (B);
   end Gen_Data_Le16;

   procedure Gen_Data_32 (Sym : Symbol; Offset : Integer_32) is
   begin
      if Dump_Asm then
         if Sym = Null_Symbol then
            Put_Line (HT & ".word 0x" & Hex_Image (Offset));
         else
            if Offset = 0 then
               Put_Line (HT & ".word " & Get_Symbol_Name (Sym));
            else
               Put_Line (HT & ".word " & Get_Symbol_Name (Sym) & " + "
                         & Hex_Image (Offset));
            end if;
         end if;
      end if;
      case Arch is
         when Arch_X86 =>
            Gen_X86_32 (Sym, Offset);
         when Arch_Sparc =>
            Gen_Sparc_32 (Sym, Offset);
         when others =>
            raise Program_Error;
      end case;
   end Gen_Data_32;

   function Create_Symbol (Name : O_Ident) return Symbol
   is
   begin
      Symbols.Append (Symbol_Type'(Section => null,
                                   Value => 0,
                                   Scope => Sym_Undef,
                                   Used => False,
                                   Name => Name,
                                   Relocs => null,
                                   Number => 0));
      return Symbols.Last;
   end Create_Symbol;

   Last_Label : Natural := 1;

   function Create_Local_Symbol return Symbol is
   begin
      Symbols.Append (Symbol_Type'(Section => Cur_Sect,
                                   Value => 0,
                                   Scope => Sym_Local,
                                   Used => False,
                                   Name => O_Ident_Nul,
                                   Relocs => null,
                                   Number => Last_Label));

      Last_Label := Last_Label + 1;

      return Symbols.Last;
   end Create_Local_Symbol;

   function Get_Symbol_Name (Sym : Symbol) return String
   is
      Res : String (1 .. 10);
      N : Natural;
      P : Natural;
   begin
      if S_Local (Sym) then
         N := Get_Number (Sym);
         P := Res'Last;
         loop
            Res (P) := Character'Val ((N mod 10) + Character'Pos ('0'));
            N := N / 10;
            P := P - 1;
            exit when N = 0;
         end loop;
         Res (P) := 'L';
         Res (P - 1) := '.';
         return Res (P - 1 .. Res'Last);
      else
         if Is_Nul (Get_Name (Sym)) then
            return "ANON";
         else
            return Get_String (Get_Name (Sym));
         end if;
      end if;
   end Get_Symbol_Name;

   function Get_Symbol_Name_Length (Sym : Symbol) return Natural
   is
      N : Natural;
   begin
      if S_Local (Sym) then
         N := 10;
         for I in 3 .. 8 loop
            if Get_Number (Sym) < N then
               return I;
            end if;
            N := N * 10;
         end loop;
         raise Program_Error;
      else
         return Get_String_Length (Get_Name (Sym));
      end if;
   end Get_Symbol_Name_Length;

   function Get_Symbol (Name : String) return Symbol is
   begin
      for I in Symbols.First .. Symbols.Last loop
         if Get_Symbol_Name (I) = Name then
            return I;
         end if;
      end loop;
      return Null_Symbol;
   end Get_Symbol;

   function Pow_Align (V : Pc_Type; Align : Natural) return Pc_Type
   is
      Tmp : Pc_Type;
   begin
      Tmp := V + 2 ** Align - 1;
      return Tmp - (Tmp mod Pc_Type (2 ** Align));
   end Pow_Align;

   procedure Gen_Pow_Align (Align : Natural) is
   begin
      if Align = 0 then
         return;
      end if;
      if Dump_Asm then
         Put_Line (HT & ".align" & Natural'Image (Align));
      end if;
      Cur_Sect.Pc := Pow_Align (Cur_Sect.Pc, Align);
   end Gen_Pow_Align;

   --  Generate LENGTH bytes set to 0.
   procedure Gen_Space (Length : Integer_32) is
   begin
      if Dump_Asm then
         Put_Line (HT & ".space" & Integer_32'Image (Length));
      end if;
      Cur_Sect.Pc := Cur_Sect.Pc + Pc_Type (Length);
   end Gen_Space;

   procedure Set_Symbol_Pc (Sym : Symbol; Export : Boolean) is
   begin
      case Get_Scope (Sym) is
         when Sym_Local =>
            if Export then
               raise Program_Error;
            end if;
         when Sym_Private
           | Sym_Global =>
            raise Program_Error;
         when Sym_Undef =>
            if Export then
               Set_Scope (Sym, Sym_Global);
            else
               Set_Scope (Sym, Sym_Private);
            end if;
      end case;
      --  Set value/section.
      Set_Symbol_Value (Sym, Cur_Sect.Pc);
      Set_Section (Sym, Cur_Sect);

      if Dump_Asm then
         if Export then
            Put_Line (HT & ".globl " & Get_Symbol_Name (Sym));
         end if;
         Put (Get_Symbol_Name (Sym));
         Put_Line (":");
      end if;
   end Set_Symbol_Pc;

   procedure Add_Reloc (Sym : Symbol; Kind : Reloc_Kind)
   is
      Reloc : Reloc_Acc;
   begin
      Reloc := new Reloc_Type'(Kind => Kind,
                               Done => False,
                               Sym_Next => Get_Relocs (Sym),
                               Sect_Next => null,
                               Addr => Cur_Sect.Pc,
                               Sym => Sym);
      Set_Relocs (Sym, Reloc);
      if Cur_Sect.First_Reloc = null then
         Cur_Sect.First_Reloc := Reloc;
      else
         Cur_Sect.Last_Reloc.Sect_Next := Reloc;
      end if;
      Cur_Sect.Last_Reloc := Reloc;
      Cur_Sect.Nbr_Relocs := Cur_Sect.Nbr_Relocs + 1;
   end Add_Reloc;

   procedure Gen_X86_Pc32 (Sym : Symbol)
   is
   begin
      Add_Reloc (Sym, Reloc_Pc32);
      Gen_Le32 (16#ff_ff_ff_fc#);
   end Gen_X86_Pc32;

   procedure Gen_Sparc_Disp22 (W : Unsigned_32; Sym : Symbol)
   is
   begin
      Add_Reloc (Sym, Reloc_Disp22);
      Gen_Be32 (W);
   end Gen_Sparc_Disp22;

   procedure Gen_Sparc_Disp30 (W : Unsigned_32; Sym : Symbol)
   is
   begin
      Add_Reloc (Sym, Reloc_Disp30);
      Gen_Be32 (W);
   end Gen_Sparc_Disp30;

   procedure Gen_Sparc_Hi22 (W : Unsigned_32;
                             Sym : Symbol; Off : Unsigned_32)
   is
      pragma Unreferenced (Off);
   begin
      Add_Reloc (Sym, Reloc_Hi22);
      Gen_Be32 (W);
   end Gen_Sparc_Hi22;

   procedure Gen_Sparc_Lo10 (W : Unsigned_32;
                             Sym : Symbol; Off : Unsigned_32)
   is
      pragma Unreferenced (Off);
   begin
      Add_Reloc (Sym, Reloc_Lo10);
      Gen_Be32 (W);
   end Gen_Sparc_Lo10;

   function Conv is new Ada.Unchecked_Conversion
     (Source => Integer_32, Target => Unsigned_32);

   procedure Gen_X86_32 (Sym : Symbol; Offset : Integer_32) is
   begin
      if Sym /= Null_Symbol then
         Add_Reloc (Sym, Reloc_32);
      end if;
      Gen_Le32 (Conv (Offset));
   end Gen_X86_32;

   procedure Gen_Sparc_32 (Sym : Symbol; Offset : Integer_32) is
   begin
      if Sym /= Null_Symbol then
         Add_Reloc (Sym, Reloc_32);
      end if;
      Gen_Be32 (Conv (Offset));
   end Gen_Sparc_32;

   procedure Gen_Sparc_Ua_32 (Sym : Symbol; Offset : Integer_32)
   is
      pragma Unreferenced (Offset);
   begin
      if Sym /= Null_Symbol then
         Add_Reloc (Sym, Reloc_Ua_32);
      end if;
      Gen_Be32 (0);
   end Gen_Sparc_Ua_32;

   procedure Gen_Ua_32 (Sym : Symbol; Offset : Integer_32) is
   begin
      case Arch is
         when Arch_X86 =>
            Gen_X86_32 (Sym, Offset);
         when Arch_Sparc =>
            Gen_Sparc_Ua_32 (Sym, Offset);
         when others =>
            raise Program_Error;
      end case;
   end Gen_Ua_32;

   procedure Gen_Ppc_24 (V : Unsigned_32; Sym : Symbol)
   is
   begin
      Add_Reloc (Sym, Reloc_Ppc_Addr24);
      Gen_32 (V);
   end Gen_Ppc_24;

   function Get_Symbol_Vaddr (Sym : Symbol) return Pc_Type is
   begin
      return Get_Section (Sym).Vaddr + Get_Symbol_Value (Sym);
   end Get_Symbol_Vaddr;

   procedure Write_Left_Be32 (Sect : Section_Acc;
                              Addr : Pc_Type;
                              Size : Natural;
                              Val : Unsigned_32)
   is
      W : Unsigned_32;
      Mask : Unsigned_32;
   begin
      --  Write value.
      Mask := Shift_Left (1, Size) - 1;
      W := Read_Be32 (Sect, Addr);
      Write_Be32 (Sect, Addr, (W and not Mask) or (Val and Mask));
   end Write_Left_Be32;

   procedure Set_Wdisp (Sect : Section_Acc;
                        Addr : Pc_Type;
                        Sym : Symbol;
                        Size : Natural)
   is
      D : Unsigned_32;
      Mask : Unsigned_32;
   begin
      D := Unsigned_32 (Get_Symbol_Vaddr (Sym) - (Sect.Vaddr + Addr));
      --  Check overflow.
      Mask := Shift_Left (1, Size + 2) - 1;
      if (D and Shift_Left (1, Size + 1)) = 0 then
         if (D and not Mask) /= 0 then
            raise Program_Error;
         end if;
      else
         if (D and not Mask) /= not Mask then
            raise Program_Error;
         end if;
      end if;
      --  Write value.
      Write_Left_Be32 (Sect, Addr, Size, D / 4);
   end Set_Wdisp;

   procedure Do_Reloc (Kind : Reloc_Kind;
                       Sect : Section_Acc; Addr : Pc_Type; Sym : Symbol)
   is
   begin
      if Get_Scope (Sym) = Sym_Undef then
         raise Program_Error;
      end if;

      case Kind is
         when Reloc_32 =>
            Add_Le32 (Sect, Addr, Unsigned_32 (Get_Symbol_Vaddr (Sym)));

         when Reloc_Pc32 =>
            Add_Le32 (Sect, Addr,
                      Unsigned_32 (Get_Symbol_Vaddr (Sym)
                                     - (Sect.Vaddr + Addr)));
         when Reloc_Disp22 =>
            Set_Wdisp (Sect, Addr, Sym, 22);
         when Reloc_Disp30 =>
            Set_Wdisp (Sect, Addr, Sym, 30);
         when Reloc_Hi22 =>
            Write_Left_Be32 (Sect, Addr, 22,
                             Unsigned_32 (Get_Symbol_Vaddr (Sym) / 1024));
         when Reloc_Lo10 =>
            Write_Left_Be32 (Sect, Addr, 10,
                             Unsigned_32 (Get_Symbol_Vaddr (Sym)));
         when Reloc_Ua_32 =>
            Write_Be32 (Sect, Addr, Unsigned_32 (Get_Symbol_Vaddr (Sym)));
         when Reloc_Ppc_Addr24 =>
            raise Program_Error;
      end case;
   end Do_Reloc;

   function Is_Reloc_Relative (Reloc : Reloc_Acc) return Boolean is
   begin
      case Reloc.Kind is
         when Reloc_Pc32
           | Reloc_Disp22
           | Reloc_Disp30 =>
            return True;
         when others =>
            return False;
      end case;
   end Is_Reloc_Relative;

   procedure Apply_Reloc (Sect : Section_Acc; Reloc : Reloc_Acc) is
   begin
      Do_Reloc (Reloc.Kind, Sect, Reloc.Addr, Reloc.Sym);
   end Apply_Reloc;

   procedure Do_Intra_Section_Reloc (Sect : Section_Acc)
   is
      Prev : Reloc_Acc;
      Rel : Reloc_Acc;
      Next : Reloc_Acc;
   begin
      Rel := Sect.First_Reloc;
      Prev := null;
      while Rel /= null loop
         Next := Rel.Sect_Next;
         if Get_Scope (Rel.Sym) /= Sym_Undef then
            Do_Reloc (Rel.Kind, Sect, Rel.Addr, Rel.Sym);
            Rel.Done := True;

            if Get_Section (Rel.Sym) = Sect
              and then Is_Reloc_Relative (Rel)
            then
               --  Remove reloc.
               Sect.Nbr_Relocs := Sect.Nbr_Relocs - 1;
               if Prev = null then
                  Sect.First_Reloc := Next;
               else
                  Prev.Sect_Next := Next;
               end if;
               if Next = null then
                  Sect.Last_Reloc := Prev;
               end if;
               Free (Rel);
            else
               Prev := Rel;
            end if;
         else
            Set_Used (Rel.Sym, True);
            Prev := Rel;
         end if;
         Rel := Next;
      end loop;
   end Do_Intra_Section_Reloc;

   --  Return VAL rounded up to 2 ^ POW.
--    function Align_Pow (Val : Integer; Pow : Natural) return Integer
--    is
--       N : Integer;
--       Tmp : Integer;
--    begin
--       N := 2 ** Pow;
--       Tmp := Val + N - 1;
--       return Tmp - (Tmp mod N);
--    end Align_Pow;

   procedure Disp_Stats is
   begin
      Put_Line ("Number of Symbols: " & Symbol'Image (Symbols.Last));
   end Disp_Stats;

   procedure Finish
   is
      Sect : Section_Acc;
      Rel, N_Rel : Reloc_Acc;
   begin
      Symbols.Free;
      Sect := Section_Chain;
      while Sect /= null loop
         --  Free relocs.
         Rel := Sect.First_Reloc;
         while Rel /= null loop
            N_Rel := Rel.Sect_Next;
            Free (Rel);
            Rel := N_Rel;
         end loop;
         Sect.First_Reloc := null;
         Sect.Last_Reloc := null;

         Sect := Sect.Next;
      end loop;
   end Finish;
end Binary_File;
