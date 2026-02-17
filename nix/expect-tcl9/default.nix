# =============================================================================
# Expect 5.45.4 compiled against Tcl 9.0 (Local Build)
# =============================================================================
#
# TODO: Remove this local build once the nixpkgs PR is merged:
#   https://github.com/NixOS/nixpkgs/pull/490930
#
# After merge, use: pkgs.tclPackages_9_0.expect
#
# =============================================================================

{ pkgs ? import <nixpkgs> {} }:

let
  tcl9 = pkgs.tcl-9_0;
in
pkgs.stdenv.mkDerivation {
  name = "expect-tcl9";
  version = "5.45.4";
  src = pkgs.expect.src;

  nativeBuildInputs = with pkgs; [ autoreconfHook pkg-config makeWrapper ];
  buildInputs = [ tcl9 ];

  # Apply nixpkgs patches first, then our Tcl 9 patches
  patches = (pkgs.expect.patches or []) ++ [
    ./tcl9-channel.patch  # Channel driver: TCL_CHANNEL_VERSION_5 with close2Proc
    ./tcl9-size.patch     # Function signatures: int objc -> Tcl_Size objc
  ];

  postPatch = ''
    # =========================================================================
    # Tcl 9 Compatibility - Source Transformations
    # =========================================================================

    # --- Path fix for stty ---
    sed -i "s,/bin/stty,stty,g" configure.in

    # --- Create Tcl 9 compatibility header ---
    #
    # IMPORTANT: The Tcl_EvalTokens wrapper MUST be OUTSIDE the include guard!
    # It uses Tcl types that aren't defined until tcl.h is included.
    # The _TCL macro is defined by tcl.h, so the wrapper compiles only after.

    cat > tcl9_compat.h << 'EOF'
/*
 * Tcl 9.0 Compatibility Layer for Expect
 */
#ifndef TCL9_COMPAT_H
#define TCL9_COMPAT_H

#include <stdarg.h>

/* Removed ANSI compatibility macros */
#ifndef _ANSI_ARGS_
#define _ANSI_ARGS_(x) x
#endif

/* Removed const macros */
#ifndef CONST
#define CONST const
#endif
#ifndef CONST84
#define CONST84 const
#endif
#ifndef CONST86
#define CONST86 const
#endif

/* Removed varargs macros */
#ifndef TCL_VARARGS
#define TCL_VARARGS(type, name) (type name, ...)
#endif
#ifndef TCL_VARARGS_DEF
#define TCL_VARARGS_DEF(type, name) (type name, ...)
#endif
#ifndef TCL_VARARGS_START
#define TCL_VARARGS_START(type, name, list) (va_start(list, name), name)
#endif

/* Renamed Unicode functions (now UTF-based) */
#ifndef Tcl_UniCharNcmp
#define Tcl_UniCharNcmp Tcl_UtfNcmp
#endif
#ifndef Tcl_UniCharNcasecmp
#define Tcl_UniCharNcasecmp Tcl_UtfNcasecmp
#endif

#endif /* TCL9_COMPAT_H */

/*
 * Tcl_EvalTokens wrapper - MUST be outside the include guard!
 */
#if defined(_TCL) && !defined(TCL9_EVALTOKENS_DEFINED)
#define TCL9_EVALTOKENS_DEFINED
static inline Tcl_Obj* Tcl_EvalTokens_Compat(
    Tcl_Interp *interp, Tcl_Token *tokenPtr, Tcl_Size count)
{
    if (Tcl_EvalTokensStandard(interp, tokenPtr, count) != TCL_OK) return NULL;
    Tcl_Obj *result = Tcl_GetObjResult(interp);
    Tcl_IncrRefCount(result);
    return result;
}
#define Tcl_EvalTokens Tcl_EvalTokens_Compat
#endif
EOF

    # --- Prepend compat header to all source files ---
    for f in *.h; do
      [ "$f" != "tcl9_compat.h" ] && sed -i '1i #include "tcl9_compat.h"' "$f"
    done
    for f in *.c; do
      sed -i '1i #include "tcl9_compat.h"' "$f"
    done

    # --- Fix Tcl stubs version ---
    sed -i 's/Tcl_InitStubs(interp, "8.1"/Tcl_InitStubs(interp, "9.0"/g' exp_main_sub.c

    # =========================================================================
    # Tcl_Size Fixes - CRITICAL: Prevents Stack Buffer Overflow
    # =========================================================================
    #
    # In Tcl 9, APIs like Tcl_GetUnicodeFromObj write Tcl_Size (8 bytes) to
    # the length pointer. Passing int* (4 bytes) causes stack buffer overflow
    # ("stack smashing detected").

    # --- Fix Tcl_GetUnicodeFromObj length parameters ---
    sed -i 's/int strlen;$/Tcl_Size strlen;/' expect.c
    sed -i 's/int plen;$/Tcl_Size plen;/' expect.c

    # --- Fix Tcl_RegExpInfo match indices ---
    sed -i 's/int start, end;/Tcl_Size start, end;/g' expect.c
    sed -i 's/int match;.*\*.*chars that matched/Tcl_Size match; \/* # of chars that matched/g' expect.c
    sed -i 's/int match = -1;.*characters matched/Tcl_Size match = -1;\t\t\/* characters matched/g' expect.c
  '';

  configureFlags = [
    "--with-tcl=${tcl9}/lib"
    "--with-tclinclude=${tcl9}/include"
    "--enable-shared"
  ];

  hardeningDisable = [ "format" ];
  env.NIX_CFLAGS_COMPILE = "-Wno-incompatible-pointer-types -Wno-int-conversion -Wno-discarded-qualifiers -std=gnu17";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/lib/expect5.45.4 $out/share/man/man1 $out/share/man/man3

    # Install library
    cp libexpect5.45.4.so $out/lib/expect5.45.4/

    # Install binary
    cp expect $out/bin/

    # Create pkgIndex
    cat > $out/lib/expect5.45.4/pkgIndex.tcl << 'PKGEOF'
if {![package vsatisfies [package provide Tcl] 9.0]} {return}
package ifneeded Expect 5.45.4 [list load [file join $dir libexpect5.45.4.so]]
PKGEOF

    # Install man pages
    cp expect.man $out/share/man/man1/expect.1 || true
    cp libexpect.man $out/share/man/man3/libexpect.3 || true

    # Wrap binary
    wrapProgram $out/bin/expect \
      --prefix PATH : ${pkgs.lib.makeBinPath [ tcl9 ]} \
      --prefix LD_LIBRARY_PATH : $out/lib/expect5.45.4 \
      --set TCLLIBPATH $out/lib/expect5.45.4

    runHook postInstall
  '';

  meta = {
    description = "Expect 5.45.4 with Tcl 9.0 support";
    homepage = "https://expect.sourceforge.net/";
    mainProgram = "expect";
  };
}
