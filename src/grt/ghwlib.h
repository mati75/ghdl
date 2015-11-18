/*  GHDL Wavefile reader library.
    Copyright (C) 2005 Tristan Gingold

    GHDL is free software; you can redistribute it and/or modify it under
    the terms of the GNU General Public License as published by the Free
    Software Foundation; either version 2, or (at your option) any later
    version.

    GHDL is distributed in the hope that it will be useful, but WITHOUT ANY
    WARRANTY; without even the implied warranty of MERCHANTABILITY or
    FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
    for more details.

    You should have received a copy of the GNU General Public License
    along with GCC; see the file COPYING.  If not, write to the Free
    Software Foundation, 59 Temple Place - Suite 330, Boston, MA
    02111-1307, USA.
*/


#ifndef _GHWLIB_H_
#define _GHWLIB_H_

#include <stdio.h>
#include <stdlib.h>

#ifdef __GNUC__
#include <stdint.h>
#endif

enum ghdl_rtik {
  ghdl_rtik_top,		/* 0  */
  ghdl_rtik_library,
  ghdl_rtik_package,
  ghdl_rtik_package_body,
  ghdl_rtik_entity,
  ghdl_rtik_architecture,	/* 5 */
  ghdl_rtik_process,
  ghdl_rtik_block,
  ghdl_rtik_if_generate,
  ghdl_rtik_for_generate,
  ghdl_rtik_instance,
  ghdl_rtik_constant,
  ghdl_rtik_iterator,
  ghdl_rtik_variable,
  ghdl_rtik_signal,
  ghdl_rtik_file,
  ghdl_rtik_port,
  ghdl_rtik_generic,
  ghdl_rtik_alias,
  ghdl_rtik_guard,
  ghdl_rtik_component,
  ghdl_rtik_attribute,
  ghdl_rtik_type_b2,		/* 22 */
  ghdl_rtik_type_e8,
  ghdl_rtik_type_e32,
  ghdl_rtik_type_i32,		/* 25 */
  ghdl_rtik_type_i64,
  ghdl_rtik_type_f64,
  ghdl_rtik_type_p32,
  ghdl_rtik_type_p64,
  ghdl_rtik_type_access,	/* 30 */
  ghdl_rtik_type_array,
  ghdl_rtik_type_record,
  ghdl_rtik_type_file,
  ghdl_rtik_subtype_scalar,
  ghdl_rtik_subtype_array,	/* 35 */
  ghdl_rtik_subtype_array_ptr,
  ghdl_rtik_subtype_unconstrained_array,
  ghdl_rtik_subtype_record,
  ghdl_rtik_subtype_access,
  ghdl_rtik_type_protected,
  ghdl_rtik_element,
  ghdl_rtik_unit,
  ghdl_rtik_attribute_transaction,
  ghdl_rtik_attribute_quiet,
  ghdl_rtik_attribute_stable,
  ghdl_rtik_error
};

/* Well-known types.  */
enum ghw_wkt_type {
  ghw_wkt_unknown,
  ghw_wkt_boolean,
  ghw_wkt_bit,
  ghw_wkt_std_ulogic
};

struct ghw_range_b2
{
  enum ghdl_rtik kind : 8;
  int dir : 8; /* 0: to, !0: downto.  */
  unsigned char left;
  unsigned char right;
};

struct ghw_range_e8
{
  enum ghdl_rtik kind : 8;
  int dir : 8; /* 0: to, !0: downto.  */
  unsigned char left;
  unsigned char right;
};

struct ghw_range_i32
{
  enum ghdl_rtik kind : 8;
  int dir : 8; /* 0: to, !0: downto.  */
  int32_t left;
  int32_t right;
};

struct ghw_range_i64
{
  enum ghdl_rtik kind : 8;
  int dir : 8;
  int64_t left;
  int64_t right;
};

struct ghw_range_f64
{
  enum ghdl_rtik kind : 8;
  int dir : 8;
  double left;
  double right;
};

union ghw_range
{
  enum ghdl_rtik kind : 8;
  struct ghw_range_e8 e8;
  struct ghw_range_i32 i32;
  struct ghw_range_i64 i64;
  struct ghw_range_f64 f64;
};

/* Note: the first two fields must be kind and name.  */
union ghw_type;

struct ghw_type_common
{
  enum ghdl_rtik kind;
  const char *name;
};

struct ghw_type_enum
{
  enum ghdl_rtik kind;
  const char *name;

  enum ghw_wkt_type wkt;
  unsigned int nbr;
  const char **lits;
};

struct ghw_type_scalar
{
  enum ghdl_rtik kind;
  const char *name;
};

struct ghw_unit
{
  const char *name;
  int64_t val;
};

struct ghw_type_physical
{
  enum ghdl_rtik kind;
  const char *name;
  uint32_t nbr_units;
  struct ghw_unit *units;
};

struct ghw_type_array
{
  enum ghdl_rtik kind;
  const char *name;

  unsigned int nbr_dim;
  union ghw_type *el;
  union ghw_type **dims;
};

struct ghw_subtype_array
{
  enum ghdl_rtik kind;
  const char *name;

  struct ghw_type_array *base;
  int nbr_el;
  union ghw_range **rngs;
};

struct ghw_subtype_scalar
{
  enum ghdl_rtik kind;
  const char *name;

  union ghw_type *base;
  union ghw_range *rng;
};

struct ghw_record_element
{
  const char *name;
  union ghw_type *type;
};

struct ghw_type_record
{
  enum ghdl_rtik kind;
  const char *name;

  unsigned int nbr_fields;
  int nbr_el;	/* Number of scalar signals.  */
  struct ghw_record_element *el;
};
  
union ghw_type
{
  enum ghdl_rtik kind;
  struct ghw_type_common common;
  struct ghw_type_enum en;
  struct ghw_type_scalar sc;
  struct ghw_type_physical ph;
  struct ghw_subtype_scalar ss;
  struct ghw_subtype_array sa;
  struct ghw_type_array ar;
  struct ghw_type_record rec;
};

union ghw_val
{
  unsigned char b2;
  unsigned char e8;
  int32_t i32;
  int64_t i64;
  double f64;
};

/* A non-composite signal.  */
struct ghw_sig
{
  union ghw_type *type;
  union ghw_val *val;
};

enum ghw_hie_kind {
  ghw_hie_eoh          = 0,
  ghw_hie_design       = 1,
  ghw_hie_block        = 3,
  ghw_hie_generate_if  = 4,
  ghw_hie_generate_for = 5,
  ghw_hie_instance     = 6,
  ghw_hie_package      = 7,
  ghw_hie_process      = 13,
  ghw_hie_generic      = 14,
  ghw_hie_eos          = 15,
  ghw_hie_signal       = 16,
  ghw_hie_port_in      = 17,
  ghw_hie_port_out     = 18,
  ghw_hie_port_inout   = 19,
  ghw_hie_port_buffer  = 20,
  ghw_hie_port_linkage = 21
};

struct ghw_hie
{
  enum ghw_hie_kind kind;
  struct ghw_hie *parent;
  const char *name;
  struct ghw_hie *brother;
  union
  {
    struct
    {
      struct ghw_hie *child;
      union ghw_type *iter_type;
      union ghw_val *iter_value;
    } blk;
    struct
    {
      union ghw_type *type;
      /* Array of signal elements.
	 Last element is 0.  */
      unsigned int *sigs;
    } sig;
  } u;
};

struct ghw_handler
{
  FILE *stream;
  /* True if words are big-endian.  */
  int word_be;
  int word_len;
  int off_len;
  /* Minor version.  */
  int version;

  /* Set by user.  */
  int flag_verbose;

  /* String table.  */
  /* Number of strings.  */
  int nbr_str;
  /* Size of the strings (without nul).  */
  int str_size;
  /* String table.  */
  char **str_table;
  /* Array containing strings.  */
  char *str_content;

  /* Type table.  */
  int nbr_types;
  union ghw_type **types;

  /* Non-composite (or basic) signals.  */
  int nbr_sigs;
  struct ghw_sig *sigs;

  /* Hierarchy.  */
  struct ghw_hie *hie;

  /* Time of the next cycle.  */
  int64_t snap_time;
};

/* Open a GHW file with H.
   Return < 0 in case of error. */
int ghw_open (struct ghw_handler *h, const char *filename);

union ghw_type *ghw_get_base_type (union ghw_type *t);

/* Put the ASCII representation of VAL into BUF, whose size if LEN.
   A NUL is always written to BUF.  */
void ghw_get_value (char *buf, int len, 
		    union ghw_val *val, union ghw_type *type);

const char *ghw_get_hie_name (struct ghw_hie *h);

void ghw_disp_hie (struct ghw_handler *h, struct ghw_hie *top);

int ghw_read_base (struct ghw_handler *h);

void ghw_disp_values (struct ghw_handler *h);

int ghw_read_cycle_start (struct ghw_handler *h);

int ghw_read_cycle_cont (struct ghw_handler *h, int *list);

int ghw_read_cycle_next (struct ghw_handler *h);

int ghw_read_cycle_end (struct ghw_handler *h);

enum ghw_sm_type {
  /* At init;
     Read section name.  */
  ghw_sm_init = 0,
  ghw_sm_sect = 1,
  ghw_sm_cycle = 2
};

enum ghw_res {
  ghw_res_error = -1,
  ghw_res_eof = -2,
  ghw_res_ok = 0,
  ghw_res_snapshot = 1,
  ghw_res_cycle = 2,
  ghw_res_other = 3
};

int ghw_read_sm (struct ghw_handler *h, enum ghw_sm_type *sm);

int ghw_read_dump (struct ghw_handler *h);

struct ghw_section {
  const char name[4];
  int (*handler)(struct ghw_handler *h);
};

extern struct ghw_section ghw_sections[];

int ghw_read_section (struct ghw_handler *h);

void ghw_close (struct ghw_handler *h);

const char *ghw_get_dir (int is_downto);

/* Note: TYPE must be a base type (used only to display literals).  */
void ghw_disp_range (union ghw_type *type, union ghw_range *rng);

void ghw_disp_type (struct ghw_handler *h, union ghw_type *t);

void ghw_disp_types (struct ghw_handler *h);
#endif /* _GHWLIB_H_ */
