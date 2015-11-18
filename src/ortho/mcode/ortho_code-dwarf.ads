--  Mcode back-end for ortho - Dwarf generator.
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
package Ortho_Code.Dwarf is
   procedure Init;
   procedure Finish;

   --  For a body.
   procedure Emit_Subprg (Bod : O_Dnode);

   --  Emit all debug info until but not including LAST.
   procedure Emit_Decls_Until (Last : O_Dnode);

   --  For a line in a subprogram.
   procedure Set_Line_Stmt (Line : Int32);
   procedure Set_Filename (Dir : String; File : String);

   type Mark_Type is limited private;
   procedure Mark (M : out Mark_Type);
   procedure Release (M : Mark_Type);

private
   type Mark_Type is record
      Last_Decl : O_Dnode;
      Last_Tnode : O_Tnode;
   end record;
end Ortho_Code.Dwarf;
