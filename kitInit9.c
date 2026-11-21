/*
 * kitInit9.c --
 *
 *	Application init for the Tcl 9 flavour of Tclkit.
 *
 *	Tcl 9 has zipfs built in, so no Metakit/vlerq/tclvfs is involved: the
 *	runtime library lives in a zip archive appended to the executable and
 *	is mounted by the core at //zipfs:/app before anything else runs.
 *
 *	This file only adds what the stock tclsh/wish do not do:
 *	  - register the statically linked extensions
 *	  - make "tclkit app.zip" (or app.kit / app.zkit) work: the archive is
 *	    mounted and its main.tcl becomes the startup script
 *	  - define ::tcl::kitpath like the 8.x tclkits
 *
 *	It is compiled together with the unmodified tclAppInit.c / winMain.c,
 *	which call us through TCL_LOCAL_APPINIT / TK_LOCAL_APPINIT.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 */

#ifdef KIT_INCLUDES_TK
#include <tk.h>
#else
#include <tcl.h>
#endif

/* The regular init procedure of tclAppInit.c or winMain.c. */
extern int Tcl_AppInit(Tcl_Interp *interp);

#ifdef KIT_INCLUDES_THREAD
extern Tcl_LibraryInitProc Thread_Init;
#endif
#ifdef KIT_INCLUDES_ITCL
extern Tcl_LibraryInitProc Itcl_Init;
extern Tcl_LibraryInitProc Itcl_SafeInit;
#endif
#ifdef KIT_INCLUDES_SQLITE
extern Tcl_LibraryInitProc Sqlite3_Init;
extern Tcl_LibraryInitProc Sqlite3_SafeInit;
#endif

/*
 * Evaluated once in the main interpreter after the normal initialisation.
 * ::tclkit::boot returns the new startup script, or an empty string to leave
 * it as is.
 */

static const char bootScript[] =
"namespace eval ::tclkit {}\n"
"set ::tcl::kitpath [info nameofexecutable]\n"
"proc ::tclkit::boot {script} {\n"
"    set lib [zipfs root]app/lib\n"
"    if {[file isdirectory $lib] && $lib ni $::auto_path} {\n"
"        lappend ::auto_path $lib\n"
"    }\n"
"    if {$script eq {} && [lindex $::argv 0] eq {-wrap}} {\n"
"        package require tclkit::wrap\n"
"        exit [::tclkit::wrap::main [lrange $::argv 1 end]]\n"
"    }\n"
"    if {$script eq {} || ![file isfile $script]} return\n"
"    if {[string match [zipfs root]* [file normalize $script]]} return\n"
"    set ext [string tolower [file extension $script]]\n"
"    if {$ext ni {.zip .kit .zkit}} {\n"
"        if {[catch {\n"
"            set f [open $script rb]\n"
"            set sig [read $f 4]\n"
"            close $f\n"
"        }] || $sig ne \"PK\\x03\\x04\"} return\n"
"    }\n"
"    set mnt [zipfs root]kit/[file rootname [file tail $script]]\n"
"    if {[catch {zipfs mount $script $mnt}]} return\n"
"    if {![file isfile $mnt/main.tcl]} {\n"
"        zipfs unmount $mnt\n"
"        return\n"
"    }\n"
"    set ::tclkit::topdir $mnt\n"
"    set ::tclkit::archive [file normalize $script]\n"
"    if {[file isdirectory $mnt/lib]} {\n"
"        lappend ::auto_path $mnt/lib\n"
"    }\n"
"    return $mnt/main.tcl\n"
"}\n";

int
TclKit_AppInit(
    Tcl_Interp *interp)
{
    Tcl_Obj *script, *objv[2];
    int code;
    const char *encoding = NULL;

    if (Tcl_AppInit(interp) != TCL_OK) {
	return TCL_ERROR;
    }

#ifdef KIT_INCLUDES_THREAD
    Tcl_StaticLibrary(NULL, "Thread", Thread_Init, NULL);
#endif
#ifdef KIT_INCLUDES_ITCL
    Tcl_StaticLibrary(NULL, "Itcl", Itcl_Init, Itcl_SafeInit);
#endif
#ifdef KIT_INCLUDES_SQLITE
    Tcl_StaticLibrary(NULL, "Sqlite3", Sqlite3_Init, Sqlite3_SafeInit);
#endif

    /* Tcl 9 no longer expands "~" in file names by itself. */
    (void) Tcl_EvalEx(interp,
	    "set tcl_rcFileName [file tildeexpand ~/tclkitrc.tcl]",
	    -1, TCL_EVAL_GLOBAL);

    /*
     * "info script" is not set yet at this point, so hand the startup script
     * to the boot code as an explicit argument instead.
     */

    if (Tcl_EvalEx(interp, bootScript, -1, TCL_EVAL_GLOBAL) != TCL_OK) {
	return TCL_ERROR;
    }
    script = Tcl_GetStartupScript(&encoding);
    objv[0] = Tcl_NewStringObj("::tclkit::boot", -1);
    objv[1] = script ? script : Tcl_NewObj();
    Tcl_IncrRefCount(objv[0]);
    Tcl_IncrRefCount(objv[1]);
    code = Tcl_EvalObjv(interp, 2, objv, TCL_EVAL_GLOBAL);
    Tcl_DecrRefCount(objv[0]);
    Tcl_DecrRefCount(objv[1]);
    if (code != TCL_OK) {
	return TCL_ERROR;
    }
    if (Tcl_GetCharLength(Tcl_GetObjResult(interp)) > 0) {
	Tcl_SetStartupScript(Tcl_GetObjResult(interp), encoding);
    }
    Tcl_ResetResult(interp);
    return TCL_OK;
}
