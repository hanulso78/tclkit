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
 *	  - Windows: ::tclkit::seticon, which gives an executable other icons
 *
 *	It is compiled together with the unmodified tclAppInit.c / winMain.c,
 *	which call us through TCL_LOCAL_APPINIT / TK_LOCAL_APPINIT.
 *
 * See the file "license.terms" for information on usage and redistribution
 * of this file, and for a DISCLAIMER OF ALL WARRANTIES.
 */

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>
#endif

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


#ifdef _WIN32
/*
 *----------------------------------------------------------------------
 *
 * SetIconObjCmd --
 *
 *	::tclkit::seticon exefile icodata
 *
 *	Replaces the icons of a Windows executable with the images of an .ico
 *	file, given as its binary contents. Every icon group of the executable
 *	is replaced, so both the icon shown by Explorer and the default icon
 *	of Tk windows change. Used by "tclkit -wrap ... -icon file.ico".
 *
 *	The executable must not carry an attached archive: the resource
 *	update of Windows rewrites the file and drops data behind the image.
 *
 *----------------------------------------------------------------------
 */

#define KIT_MAXGROUPS	32
#define KIT_MAXICONS	256

typedef struct {
    int numGroups;
    LPWSTR groupName[KIT_MAXGROUPS];	/* integer id or allocated string */
    WORD groupLang[KIT_MAXGROUPS];
    int numIcons;
    WORD iconId[KIT_MAXICONS];
    WORD iconLang[KIT_MAXICONS];
} KitIcons;

static BOOL CALLBACK
KitEnumLangs(
    HMODULE module,
    LPCWSTR type,
    LPCWSTR name,
    WORD lang,
    LONG_PTR param)
{
    KitIcons *icons = (KitIcons *) param;
    HRSRC res;
    const unsigned char *data;
    DWORD size, i, count;

    if (icons->numGroups >= KIT_MAXGROUPS) {
	return FALSE;
    }
    if (IS_INTRESOURCE(name)) {
	icons->groupName[icons->numGroups] = (LPWSTR) name;
    } else {
	size_t bytes = (wcslen(name) + 1) * sizeof(WCHAR);

	icons->groupName[icons->numGroups] = (LPWSTR) Tcl_Alloc(bytes);
	memcpy(icons->groupName[icons->numGroups], name, bytes);
    }
    icons->groupLang[icons->numGroups++] = lang;

    /* remember the images of this group, they are deleted later */
    res = FindResourceExW(module, type, name, lang);
    if (res == NULL) {
	return TRUE;
    }
    data = (const unsigned char *) LockResource(LoadResource(module, res));
    size = SizeofResource(module, res);
    if (data == NULL || size < 6) {
	return TRUE;
    }
    count = data[4] | (data[5] << 8);
    for (i = 0; i < count && 6 + (i + 1) * 14 <= size; i++) {
	const unsigned char *e = data + 6 + i * 14;

	WORD id = (WORD) (e[12] | (e[13] << 8));
	int k;

	/* groups may share images; deleting one twice spoils the update */
	for (k = 0; k < icons->numIcons; k++) {
	    if (icons->iconId[k] == id && icons->iconLang[k] == lang) {
		break;
	    }
	}
	if (k == icons->numIcons && icons->numIcons < KIT_MAXICONS) {
	    icons->iconId[icons->numIcons] = id;
	    icons->iconLang[icons->numIcons++] = lang;
	}
    }
    return TRUE;
}

static BOOL CALLBACK
KitEnumNames(
    HMODULE module,
    LPCWSTR type,
    LPWSTR name,
    LONG_PTR param)
{
    EnumResourceLanguagesW(module, type, name, KitEnumLangs, param);
    return TRUE;
}

static int
SetIconObjCmd(
    void *dummy,
    Tcl_Interp *interp,
    int objc,
    Tcl_Obj *const objv[])
{
    KitIcons icons;
    const unsigned char *ico;
    unsigned char *group;
    Tcl_Size icoLen;
    const WCHAR *path;
    HMODULE module;
    HANDLE update;
    DWORD count, i;
    WORD lang;
    int ok = 1;
    const char *stage = "open";
    DWORD err = 0;
    (void) dummy;

    if (objc != 3) {
	Tcl_WrongNumArgs(interp, 1, objv, "exefile icodata");
	return TCL_ERROR;
    }
    ico = Tcl_GetBytesFromObj(interp, objv[2], &icoLen);
    if (ico == NULL) {
	return TCL_ERROR;
    }
    count = (icoLen >= 6) ? (DWORD) (ico[4] | (ico[5] << 8)) : 0;
    if (icoLen < 6 || ico[0] || ico[1] || ico[2] != 1 || ico[3]
	    || count == 0 || count > KIT_MAXICONS
	    || (Tcl_Size) (6 + count * 16) > icoLen) {
	Tcl_SetObjResult(interp, Tcl_NewStringObj("not an icon file", -1));
	return TCL_ERROR;
    }
    for (i = 0; i < count; i++) {
	const unsigned char *e = ico + 6 + i * 16;
	DWORD bytes = e[8] | (e[9] << 8) | (e[10] << 16) | ((DWORD) e[11] << 24);
	DWORD offset = e[12] | (e[13] << 8) | (e[14] << 16) | ((DWORD) e[15] << 24);

	if ((Tcl_Size) offset > icoLen || (Tcl_Size) bytes > icoLen - offset) {
	    Tcl_SetObjResult(interp,
		    Tcl_NewStringObj("damaged icon file", -1));
	    return TCL_ERROR;
	}
    }
    path = (const WCHAR *) Tcl_FSGetNativePath(objv[1]);
    if (path == NULL) {
	Tcl_SetObjResult(interp, Tcl_NewStringObj("bad file name", -1));
	return TCL_ERROR;
    }

    /* what is there now */
    memset(&icons, 0, sizeof(icons));
    module = LoadLibraryExW(path, NULL, LOAD_LIBRARY_AS_DATAFILE);
    if (module == NULL) {
	Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		"cannot read the resources of \"%s\"", Tcl_GetString(objv[1])));
	return TCL_ERROR;
    }
    EnumResourceNamesW(module, (LPCWSTR) RT_GROUP_ICON, KitEnumNames,
	    (LONG_PTR) &icons);
    FreeLibrary(module);
    if (icons.numGroups == 0) {
	icons.groupName[0] = MAKEINTRESOURCEW(1);
	icons.groupLang[0] = MAKELANGID(LANG_ENGLISH, SUBLANG_ENGLISH_US);
	icons.numGroups = 1;
    }
    lang = icons.groupLang[0];

    /* the group directory: as in the file, with an id in place of the offset */
    group = (unsigned char *) Tcl_Alloc(6 + count * 14);
    memcpy(group, ico, 6);
    for (i = 0; i < count; i++) {
	memcpy(group + 6 + i * 14, ico + 6 + i * 16, 12);
	group[6 + i * 14 + 12] = (unsigned char) ((i + 1) & 0xff);
	group[6 + i * 14 + 13] = (unsigned char) ((i + 1) >> 8);
    }

    update = BeginUpdateResourceW(path, FALSE);
    if (update == NULL) {
	ok = 0;
	err = GetLastError();
    } else {
	for (i = 0; ok && i < (DWORD) icons.numIcons; i++) {
	    UpdateResourceW(update, (LPCWSTR) RT_ICON,
		    MAKEINTRESOURCEW(icons.iconId[i]), icons.iconLang[i],
		    NULL, 0);
	}
	for (i = 0; ok && i < count; i++) {
	    const unsigned char *e = ico + 6 + i * 16;
	    DWORD bytes = e[8] | (e[9] << 8) | (e[10] << 16)
		    | ((DWORD) e[11] << 24);
	    DWORD offset = e[12] | (e[13] << 8) | (e[14] << 16)
		    | ((DWORD) e[15] << 24);

	    stage = "add image";
	    ok = UpdateResourceW(update, (LPCWSTR) RT_ICON,
		    MAKEINTRESOURCEW(i + 1), lang, (LPVOID) (ico + offset),
		    bytes);
	}
	for (i = 0; ok && i < (DWORD) icons.numGroups; i++) {
	    stage = "add group";
	    ok = UpdateResourceW(update, (LPCWSTR) RT_GROUP_ICON,
		    icons.groupName[i], icons.groupLang[i], group,
		    6 + count * 14);
	}
	if (!ok) {
	    err = GetLastError();
	    EndUpdateResourceW(update, TRUE);
	} else if (!EndUpdateResourceW(update, FALSE)) {
	    stage = "write";
	    err = GetLastError();
	    ok = 0;
	}
    }

    Tcl_Free(group);
    for (i = 0; i < (DWORD) icons.numGroups; i++) {
	if (!IS_INTRESOURCE(icons.groupName[i])) {
	    Tcl_Free(icons.groupName[i]);
	}
    }
    if (!ok) {
	Tcl_SetObjResult(interp, Tcl_ObjPrintf(
		"cannot update the resources of \"%s\" (%s, error %lu)",
		Tcl_GetString(objv[1]), stage, (unsigned long) err));
	return TCL_ERROR;
    }
    return TCL_OK;
}
#endif /* _WIN32 */

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

#ifdef _WIN32
    Tcl_CreateObjCommand(interp, "::tclkit::seticon", SetIconObjCmd, NULL,
	    NULL);
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
