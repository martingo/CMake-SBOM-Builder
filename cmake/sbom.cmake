cmake_minimum_required(VERSION 3.16 FATAL_ERROR)

# catch and stop second call to this function
if(COMMAND sbom_generate)
	return()
endif()

include(GNUInstallDirs)

find_package(Git)

set(SBOM_BUILDER_VERSION "0.0.0-development-version" CACHE STRING "CMake-SBOM-Builder version")

if(SBOM_BUILDER_VERSION MATCHES "development-version")
	message( WARNING "Your project is using an unstable development version of CMake-SBOM-Builder. \
Consider switching to a stable release. https://github.com/sodgeit/CMake-SBOM-Builder" )
endif()

function(version_show)
	message(STATUS "${PROJECT_NAME} version is ${GIT_VERSION}")
endfunction()

# Extract version information from Git of the current project.
function(version_extract)
	if(DEFINED GIT_VERSION)
		return()
	endif()

	set(_git_short_hash "unknown")
	set(_git_full_hash "unknown")
	set(_git_branch "none")
	set(_git_describe "v0.0.0-0-g${_git_short_hash}")
	set(_git_tag "v0.0.0")
	set(_git_dirty "")

	if(Git_FOUND)
		execute_process(
			COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
			WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
			OUTPUT_VARIABLE _git_short_hash
			ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE
		)

		execute_process(
			COMMAND ${GIT_EXECUTABLE} rev-parse HEAD
			WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
			OUTPUT_VARIABLE _git_full_hash
			ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE
		)

		execute_process(
			COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
			WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
			OUTPUT_VARIABLE _git_branch
			ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE
		)

		if("${_git_branch}" STREQUAL "HEAD")
			if(NOT "$ENV{CI_COMMIT_BRANCH}" STREQUAL "")
				# Probably a detached head running on a gitlab runner
				set(_git_branch "$ENV{CI_COMMIT_BRANCH}")
			endif()
		endif()

		execute_process(
			COMMAND ${GIT_EXECUTABLE} describe --tags
			WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
			OUTPUT_VARIABLE _git_describe
			ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE
		)

		# don't rely on git describe for dirty status
		# we want to be really picky and include untracked files in the dirty check
		execute_process(
			COMMAND ${GIT_EXECUTABLE} status -s
			WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
			OUTPUT_VARIABLE _git_dirty
			ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE
		)
		if(NOT "${_git_dirty}" STREQUAL "")
			set(_git_dirty "+dirty")
		endif()

		execute_process(
			COMMAND ${GIT_EXECUTABLE} tag --points-at HEAD
			WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}"
			OUTPUT_VARIABLE _git_tag
			ERROR_QUIET OUTPUT_STRIP_TRAILING_WHITESPACE
		)

		string(REGEX REPLACE "[ \t\r\n].*$" "" _git_tag "${_git_tag}")

		if("${_git_tag}" STREQUAL "")
			if(NOT "$ENV{CI_COMMIT_TAG}" STREQUAL "")
				# Probably a detached head running on a gitlab runner
				set(_git_tag "$ENV{CI_COMMIT_TAG}")
			endif()
		endif()
	else()
		message(WARNING "Git not found. Version information will use placeholders.")
	endif()

	if("$ENV{CI_BUILD_ID}" STREQUAL "")
		set(version_build "")
	else()
		set(version_build "+build$ENV{CI_BUILD_ID}")
	endif()

	# HEAD points directly to a tag
	if(NOT ${_git_tag} STREQUAL "")
		set(_git_version "${_git_tag}")
	else()
		set(_git_version "${_git_describe}+${_git_branch}${version_build}")
	endif()

	set(_git_version "${_git_version}${_git_dirty}")

	set(GIT_HASH "${_git_full_hash}" PARENT_SCOPE)
	set(GIT_HASH_SHORT "${_git_short_hash}" PARENT_SCOPE)
	set(GIT_VERSION "${_git_version}" PARENT_SCOPE)
	string(REGEX REPLACE "[^-a-zA-Z0-9_.+]+" "_" _git_version_path "${_git_version}")
	set(GIT_VERSION_PATH "${_git_version_path}" PARENT_SCOPE)

	if(_git_version MATCHES "^(v)?([0-9]+)\\.([0-9]+)\\.([0-9]+)(.+)$")
		set(GIT_VERSION_TRIPLET "${CMAKE_MATCH_2}.${CMAKE_MATCH_3}.${CMAKE_MATCH_4}" PARENT_SCOPE)
		set(GIT_VERSION_MAJOR "${CMAKE_MATCH_2}" PARENT_SCOPE)
		set(GIT_VERSION_MINOR "${CMAKE_MATCH_3}" PARENT_SCOPE)
		set(GIT_VERSION_PATCH "${CMAKE_MATCH_4}" PARENT_SCOPE)
		set(GIT_VERSION_SUFFIX "${CMAKE_MATCH_5}" PARENT_SCOPE)
	endif()

	string(TIMESTAMP VERSION_TIMESTAMP "%Y-%m-%d %H:%M:%S")
	set(VERSION_TIMESTAMP "${VERSION_TIMESTAMP}" PARENT_SCOPE)

	set(GIT_VERSION "${_git_version}") # required for version_show()
	version_show()
endfunction()

# Generate version files and a static library based on the extract version information of the
# current project.
function(version_generate)
	if(NOT DEFINED ${GIT_VERSION})
		version_extract()
	endif()

	string(TOUPPER "${PROJECT_NAME}" PROJECT_NAME_UC)
	string(REGEX REPLACE "[^A-Z0-9]+" "_" PROJECT_NAME_UC "${PROJECT_NAME_UC}")

	set(VERSION_DOC_DIR ${PROJECT_BINARY_DIR}/version/doc)
	set(VERSION_INC_DIR ${PROJECT_BINARY_DIR}/version/include)
	set(VERSION_SCRIPT_DIR ${PROJECT_BINARY_DIR}/version/scripts)

	file(
		GENERATE
		OUTPUT ${VERSION_SCRIPT_DIR}/version.sh
		CONTENT "#!/bin/bash

#This is a generated file. Do not edit.

GIT_HASH=\"${GIT_HASH}\"
GIT_HASH_SHORT=\"${GIT_HASH_SHORT}\"
GIT_VERSION=\"${GIT_VERSION}\"
GIT_VERSION_PATH=\"${GIT_VERSION_PATH}\"
VERSION_TIMESTAMP=\"${VERSION_TIMESTAMP}\"

$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>GIT_VERSION_TRIPLET=\"${GIT_VERSION_TRIPLET}\"
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>GIT_VERSION_MAJOR=${GIT_VERSION_MAJOR}
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>GIT_VERSION_MINOR=${GIT_VERSION_MINOR}
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>GIT_VERSION_PATCH=${GIT_VERSION_PATCH}
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>GIT_VERSION_SUFFIX=\"${GIT_VERSION_SUFFIX}\"
"
	)

	file(
		GENERATE
		OUTPUT ${VERSION_SCRIPT_DIR}/version.ps1
		CONTENT "#This is a generated file. Do not edit.

$GIT_HASH=\"${GIT_HASH}\"
$GIT_HASH_SHORT=\"${GIT_HASH_SHORT}\"
$GIT_VERSION=\"${GIT_VERSION}\"
$GIT_VERSION_PATH=\"${GIT_VERSION_PATH}\"
$VERSION_TIMESTAMP=\"${VERSION_TIMESTAMP}\"

$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>$GIT_VERSION_TRIPLET=\"${GIT_VERSION_TRIPLET}\"
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>$GIT_VERSION_MAJOR=${GIT_VERSION_MAJOR}
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>$GIT_VERSION_MINOR=${GIT_VERSION_MINOR}
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>$GIT_VERSION_PATCH=${GIT_VERSION_PATCH}
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>:#>$GIT_VERSION_SUFFIX=\"${GIT_VERSION_SUFFIX}\"
"
	)

	file(
		GENERATE
		OUTPUT ${VERSION_INC_DIR}/${PROJECT_NAME}_version.h
		CONTENT "// clang-format off
#ifndef ${PROJECT_NAME_UC}_VERSION_H
#define ${PROJECT_NAME_UC}_VERSION_H

/* This is a generated file. Do not edit. */

#define ${PROJECT_NAME_UC}_HASH            \"${GIT_HASH}\"
#define ${PROJECT_NAME_UC}_HASH_SHORT      \"${GIT_HASH_SHORT}\"
#define ${PROJECT_NAME_UC}_VERSION         \"${GIT_VERSION}\"
#define ${PROJECT_NAME_UC}_VERSION_PATH    \"${GIT_VERSION_PATH}\"
#define ${PROJECT_NAME_UC}_TIMESTAMP       \"${VERSION_TIMESTAMP}\"

$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>://>#define ${PROJECT_NAME_UC}_VERSION_TRIPLET \"${GIT_VERSION_TRIPLET}\"
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>://>#define ${PROJECT_NAME_UC}_VERSION_MAJOR    ${GIT_VERSION_MAJOR}
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>://>#define ${PROJECT_NAME_UC}_VERSION_MINOR    ${GIT_VERSION_MINOR}
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>://>#define ${PROJECT_NAME_UC}_VERSION_PATCH    ${GIT_VERSION_PATCH}
$<$<NOT:$<BOOL:${GIT_VERSION_TRIPLET}>>://>#define ${PROJECT_NAME_UC}_VERSION_SUFFIX  \"${GIT_VERSION_SUFFIX}\"

#endif // ${PROJECT_NAME_UC}_VERSION_H
    // clang-format on
"
	)

	file(WRITE ${VERSION_DOC_DIR}/version.txt "${GIT_VERSION}")

	if(NOT TARGET ${PROJECT_NAME}-version)
		add_library(${PROJECT_NAME}-version INTERFACE)

		target_include_directories(${PROJECT_NAME}-version INTERFACE
			"$<BUILD_INTERFACE:${VERSION_INC_DIR}>"
			"$<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>"
		)
	endif()

	set(VERSION_DOC_DIR ${VERSION_DOC_DIR} PARENT_SCOPE)
	set(VERSION_INC_DIR ${VERSION_INC_DIR} PARENT_SCOPE)
	set(VERSION_SCRIPT_DIR ${VERSION_SCRIPT_DIR} PARENT_SCOPE)

endfunction()

# Common Platform Enumeration: https://nvd.nist.gov/products/cpe
#
# TODO: This detection can be improved.
if(WIN32)
	if("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "AMD64")
		set(_arch "x64")
	elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "IA64")
		set(_arch "x64")
	elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "ARM64")
		set(_arch "arm64")
	elseif("${CMAKE_SYSTEM_PROCESSOR}" STREQUAL "X86")
		set(_arch "x86")
	elseif(CMAKE_CXX_COMPILER MATCHES "64")
		set(_arch "x64")
	elseif(CMAKE_CXX_COMPILER MATCHES "86")
		set(_arch "x86")
	else()
		set(_arch "*")
	endif()

	if("${CMAKE_SYSTEM_VERSION}" STREQUAL "6.1")
		set(SBOM_CPE "cpe:2.3:o:microsoft:windows_7:-:*:*:*:*:*:${_arch}:*")
	elseif("${CMAKE_SYSTEM_VERSION}" STREQUAL "6.2")
		set(SBOM_CPE "cpe:2.3:o:microsoft:windows_8:-:*:*:*:*:*:${_arch}:*")
	elseif("${CMAKE_SYSTEM_VERSION}" STREQUAL "6.3")
		set(SBOM_CPE "cpe:2.3:o:microsoft:windows_8.1:-:*:*:*:*:*:${_arch}:*")
	elseif(NOT "${CMAKE_SYSTEM_VERSION}" VERSION_LESS 10)
		set(SBOM_CPE "cpe:2.3:o:microsoft:windows_10:-:*:*:*:*:*:${_arch}:*")
	else()
		set(SBOM_CPE "cpe:2.3:o:microsoft:windows:-:*:*:*:*:*:${_arch}:*")
	endif()
elseif(APPLE)
	set(SBOM_CPE "cpe:2.3:o:apple:mac_os:*:*:*:*:*:*:${CMAKE_SYSTEM_PROCESSOR}:*")
elseif(UNIX)
	set(SBOM_CPE "cpe:2.3:o:canonical:ubuntu_linux:-:*:*:*:*:*:${CMAKE_SYSTEM_PROCESSOR}:*")
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "arm")
	set(SBOM_CPE "cpe:2.3:h:arm:arm:-:*:*:*:*:*:*:*")
else()
	message(FATAL_ERROR "Unsupported platform")
endif()

# Sets the given variable to a unique SPDIXID-compatible value.
function(sbom_spdxid)
	set(oneValueArgs VARIABLE CHECK)
	set(multiValueArgs HINTS)

	cmake_parse_arguments(
		SBOM_SPDXID "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN}
	)

	if(SBOM_SPDXID_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown arguments: ${SBOM_SPDXID_UNPARSED_ARGUMENTS}")
	endif()

	if(NOT DEFINED SBOM_SPDXID_VARIABLE)
		message(FATAL_ERROR "Missing VARIABLE")
	endif()

	if("${SBOM_SPDXID_CHECK}" STREQUAL "")
		get_property(_spdxids GLOBAL PROPERTY sbom_spdxids)
		set(_suffix "-${_spdxids}")
		math(EXPR _spdxids "${_spdxids} + 1")
		set_property(GLOBAL PROPERTY sbom_spdxids "${_spdxids}")

		foreach(_hint IN LISTS SBOM_SPDXID_HINTS)
			string(REGEX REPLACE "[^a-zA-Z0-9]+" "-" _id "${_hint}")
			string(REGEX REPLACE "-+$" "" _id "${_id}")

			if(NOT "${_id}" STREQUAL "")
				set(_id "${_id}${_suffix}")
				break()
			endif()
		endforeach()

		if("${_id}" STREQUAL "")
			set(_id "SPDXRef${_suffix}")
		endif()
	else()
		set(_id "${SBOM_SPDXID_CHECK}")
	endif()

	if(NOT "${_id}" MATCHES "^SPDXRef-[-a-zA-Z0-9]+$")
		message(FATAL_ERROR "Invalid SPDXID \"${_id}\"")
	endif()

	set(${SBOM_SPDXID_VARIABLE} "${_id}" PARENT_SCOPE)
endfunction()

#TODO BuiltDate should be evaluated during build, not when sbom is generated.

macro(_sbom_generate_document_template)
	set(_pkg_creator_name "")
	set(_pkg_creator_field "")
	set(_pkg_supplier_field "")
	set(_pkg_copyright_field "")

	if(DEFINED _arg_sbom_gen_CREATOR_PERSON)
		set(_pkg_creator_name "${_arg_sbom_gen_CREATOR_PERSON}")
		set(_pkg_creator_field "Creator: Person: ${_pkg_creator_name}")
		set(_pkg_supplier_field "PackageSupplier: Person: ${_pkg_creator_name}")
	elseif(DEFINED _arg_sbom_gen_CREATOR_ORGANIZATION)
		set(_pkg_creator_name "${_arg_sbom_gen_CREATOR_ORGANIZATION}")
		set(_pkg_creator_field "Creator: Organization: ${_pkg_creator_name}")
		set(_pkg_supplier_field "PackageSupplier: Organization: ${_pkg_creator_name}")
	endif()
	if(DEFINED _arg_sbom_gen_CREATOR_EMAIL)
		set(_pkg_creator_field "${_pkg_creator_field} (${_arg_sbom_gen_CREATOR_EMAIL})")
		set(_pkg_supplier_field "${_pkg_supplier_field} (${_arg_sbom_gen_CREATOR_EMAIL})")
	endif()

	if(DEFINED _arg_sbom_gen_PACKAGE_COPYRIGHT)
		set(_pkg_copyright_field "PackageCopyrightText: ${_arg_sbom_gen_PACKAGE_COPYRIGHT}")
	endif()

	set(_pkg_summary_field FALSE)
	set(_pkg_desc_field FALSE)
	if(DEFINED _arg_sbom_gen_PACKAGE_SUMMARY)
		set(_pkg_summary_field TRUE)
		set(_pkg_summary_field_txt "PackageSummary: <text$<ANGLE-R>${_arg_sbom_gen_PACKAGE_SUMMARY}</text$<ANGLE-R>")
	endif()

	if(DEFINED _arg_sbom_gen_PACKAGE_DESC)
		set(_pkg_desc_field TRUE)
		set(_pkg_desc_field_txt "PackageDescription: <text$<ANGLE-R>${_arg_sbom_gen_PACKAGE_DESC}</text$<ANGLE-R>")
	endif()

	set(_pkg_purpose_fields FALSE)
	if(DEFINED _arg_sbom_gen_PACKAGE_PURPOSE)
		set(_pkg_purpose_fields TRUE)
		set(_pkg_purpose_field_txt "")
		foreach(_purpose IN LISTS _arg_sbom_gen_PACKAGE_PURPOSE)
			set(_pkg_purpose_field_txt "${_pkg_purpose_field_txt}\nPrimaryPackagePurpose: ${_purpose}")
		endforeach()
	endif()

	file(
		GENERATE
		OUTPUT "${SBOM_SNIPPET_DIR}/${_sbom_document_template}"
		CONTENT
		"SPDXVersion: SPDX-2.3
DataLicense: CC0-1.0
SPDXID: SPDXRef-DOCUMENT
DocumentName: ${doc_name}
DocumentNamespace: ${_arg_sbom_gen_NAMESPACE}\
$<$<BOOL:${_pkg_creator_field}>:\n${_pkg_creator_field}>
Creator: Tool: CMake-SBOM-Builder-${SBOM_BUILDER_VERSION}
CreatorComment: <text>This SPDX document was created from CMake ${CMAKE_VERSION}, using CMake-SBOM-Builder from https://github.com/sodgeit/CMake-SBOM-Builder</text>
Created: \${SBOM_CREATE_DATE}
\${SBOM_EXT_DOCS}
PackageName: ${CMAKE_CXX_COMPILER_ID}
SPDXID: SPDXRef-compiler
PackageVersion: ${CMAKE_CXX_COMPILER_VERSION}
PackageDownloadLocation: NOASSERTION
PackageLicenseConcluded: NOASSERTION
PackageLicenseDeclared: NOASSERTION
PackageCopyrightText: NOASSERTION
PackageSupplier: Organization: Anonymous
FilesAnalyzed: false
PackageSummary: <text>The compiler as identified by CMake, running on ${CMAKE_HOST_SYSTEM_NAME} (${CMAKE_HOST_SYSTEM_PROCESSOR})</text>
PrimaryPackagePurpose: APPLICATION
Relationship: SPDXRef-compiler CONTAINS NOASSERTION
Relationship: SPDXRef-compiler BUILD_DEPENDENCY_OF SPDXRef-${_arg_sbom_gen_PACKAGE_NAME}
RelationshipComment: <text>SPDXRef-${_arg_sbom_gen_PACKAGE_NAME} is built by compiler ${CMAKE_CXX_COMPILER_ID} (${CMAKE_CXX_COMPILER}) version ${CMAKE_CXX_COMPILER_VERSION}</text>

PackageName: ${_arg_sbom_gen_PACKAGE_NAME}
SPDXID: SPDXRef-${_arg_sbom_gen_PACKAGE_NAME}
ExternalRef: SECURITY cpe23Type ${SBOM_CPE}
ExternalRef: PACKAGE-MANAGER purl pkg:supplier/${_pkg_creator_name}/${_arg_sbom_gen_PACKAGE_NAME}@${_arg_sbom_gen_PACKAGE_VERSION}
PackageVersion: ${_arg_sbom_gen_PACKAGE_VERSION}
PackageFileName: ${_arg_sbom_gen_PACKAGE_FILENAME}\
$<$<BOOL:${_pkg_supplier_field}>:\n${_pkg_supplier_field}>
PackageDownloadLocation: ${_arg_sbom_gen_PACKAGE_DOWNLOAD}
PackageLicenseConcluded: ${_arg_sbom_gen_PACKAGE_LICENSE}
PackageLicenseDeclared: ${_arg_sbom_gen_PACKAGE_LICENSE}\
$<$<BOOL:${_pkg_copyright_field}>:\n${_pkg_copyright_field}>
PackageHomePage: ${_arg_sbom_gen_PACKAGE_URL}\
$<$<BOOL:${_pkg_summary_field}>:\n${_pkg_summary_field_txt}>\
$<$<BOOL:${_pkg_desc_field}>:\n${_pkg_desc_field_txt}>
PackageComment: <text>Built by CMake ${CMAKE_VERSION} with $<CONFIG> configuration for ${CMAKE_SYSTEM_NAME} (${CMAKE_SYSTEM_PROCESSOR})</text>\
$<$<BOOL:${_pkg_purpose_fields}>:${_pkg_purpose_field_txt}>
PackageVerificationCode: \${SBOM_VERIFICATION_CODE}
BuiltDate: \${SBOM_CREATE_DATE}
ReleaseDate: \${SBOM_CREATE_DATE}
Relationship: SPDXRef-DOCUMENT DESCRIBES SPDXRef-${_arg_sbom_gen_PACKAGE_NAME}
"
	)
endmacro()

function(_sbom_append_sbom_snippet SNIPPET_SCRIPT)
	get_property(_sbom_binary_dir GLOBAL PROPERTY SBOM_BINARY_DIR)
	get_property(_sbom_snippet_dir GLOBAL PROPERTY SBOM_SNIPPET_DIR)
	file(APPEND ${_sbom_binary_dir}/CMakeLists.txt
		"install(SCRIPT \"\${SBOM_SNIPPET_DIR}/${SNIPPET_SCRIPT}\")\n"
	)
endfunction()

function(_sbom_parse_package_supplier pkg_supplier_arg out_supplier_type out_supplier_name out_supplier_email)
	cmake_parse_arguments(_arg_supplier "NOASSERTION" "ORGANIZATION;PERSON;EMAIL" "" ${pkg_supplier_arg})

	if(_arg_supplier_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown subarguments passed to SUPPLIER: ${_arg_supplier_UNPARSED_ARGUMENTS}")
	endif()

	if(_arg_supplier_NOASSERTION)
		set(${out_supplier_type} "NOASSERTION" PARENT_SCOPE)
		return()
	endif()
	if((NOT DEFINED _arg_supplier_PERSON) AND (NOT DEFINED _arg_supplier_ORGANIZATION))
		message(FATAL_ERROR "Missing <NOASSERTION|PERSON|ORGANIZATION> <name> for argument SUPPLIER.")
	elseif(DEFINED _arg_supplier_PERSON AND DEFINED _arg_supplier_ORGANIZATION)
		message(FATAL_ERROR "Specify either PERSON or ORGANIZATION, not both.")
	endif()

	if(DEFINED _arg_supplier_PERSON)
		set(${out_supplier_type} "Person:" PARENT_SCOPE)
		set(${out_supplier_name} "${_arg_supplier_PERSON}" PARENT_SCOPE)
	elseif(DEFINED _arg_supplier_ORGANIZATION)
		set(${out_supplier_type} "Organization:" PARENT_SCOPE)
		set(${out_supplier_name} "${_arg_supplier_ORGANIZATION}" PARENT_SCOPE)
	endif()

	if(DEFINED _arg_supplier_EMAIL)
		set(${out_supplier_email} "${_arg_supplier_EMAIL}" PARENT_SCOPE)
	endif()
endfunction()

function(_sbom_parse_license pkg_license_arg out_license_concluded out_license_declared out_license_comment)
	cmake_parse_arguments(_arg_license "" "CONCLUDED;DECLARED;COMMENT" "" ${pkg_license_arg})

	if(_arg_license_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown subarguments for LICENSE: ${_arg_license_UNPARSED_ARGUMENTS}")
	endif()

	if(DEFINED _arg_license_CONCLUDED)
		set(${out_license_concluded} "${_arg_license_CONCLUDED}" PARENT_SCOPE)
	else()
		set(${out_license_concluded} "NOASSERTION" PARENT_SCOPE)
	endif()

	if(DEFINED _arg_license_DECLARED)
		set(${out_license_declared} "${_arg_license_DECLARED}" PARENT_SCOPE)
	else()
		set(${out_license_declared} "NOASSERTION" PARENT_SCOPE)
	endif()

	if(DEFINED _arg_license_COMMENT)
		set(${out_license_comment} "${_arg_license_COMMENT}" PARENT_SCOPE)
	endif()
endfunction()

function(_sbom_parse_dates pkg_dates_arg out_BUILD out_RELEASE out_VALID_UNTIL)
	set(oneValueArgs BUILT RELEASE VALID_UNTIL)
	cmake_parse_arguments(_arg_dates "" "${oneValueArgs}" "" ${pkg_dates_arg})

	if(_arg_dates_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown subarguments for DATE: ${_arg_dates_UNPARSED_ARGUMENTS}")
	endif()

	foreach(_date ${oneValueArgs})
		if(DEFINED _arg_dates_${_date})
			string(REGEX MATCH "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" _arg_dates_${_date} ${_arg_dates_${_date}})
			if(NOT _arg_dates_${_date})
				message(FATAL_ERROR "Invalid date format for ${_date}: ${_arg_dates_${_date}}")
			endif()
			set(${out_${_date}} "${_arg_dates_${_date}}" PARENT_SCOPE)
		endif()

	endforeach()
endfunction()

function(_sbom_parse_package_notes pkg_notes_arg out_pkg_SUMMARY out_pkg_DESC out_pkg_COMMENT)
	set(oneValueArgs "SUMMARY;DESC;COMMENT")
	cmake_parse_arguments(_arg_notes "" "${oneValueArgs}" "" ${pkg_notes_arg})
	foreach(_note_type ${oneValueArgs})
		if(DEFINED _arg_notes_${_note_type})
			set(${out_pkg_${_note_type}} "${_arg_notes_${_note_type}}" PARENT_SCOPE)
		endif()
	endforeach()
endfunction()

function(_sbom_parse_package_purpose pkg_purpose_arg out_purpose_list)
	set(options "APPLICATION;FRAMEWORK;LIBRARY;CONTAINER;OPERATING-SYSTEM;DEVICE;FIRMWARE;SOURCE;ARCHIVE;FILE;INSTALL;OTHER")
	cmake_parse_arguments(_arg "${options}" "" "" ${pkg_purpose_arg})
	if(_arg_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown keywords for PURPOSE: ${_arg_UNPARSED_ARGUMENTS}")
	endif()

	set(${out_purpose_list} "")
	foreach(opt ${options})
		if(_arg_${opt})
			list(APPEND ${out_purpose_list} ${opt})
		endif()
	endforeach()

	set(${out_purpose_list} "${${out_purpose_list}}" PARENT_SCOPE)
endfunction()

function(_sbom_parse_filetype file_type_arg out_filetype_list)
	# https://spdx.github.io/spdx-spec/v2.3/file-information/#83-file-type-field
	set(valid_entries "SOURCE;BINARY;ARCHIVE;APPLICATION;AUDIO;IMAGE;TEXT;VIDEO;DOCUMENTATION;SPDX;OTHER")
	cmake_parse_arguments(_arg_filetype "${valid_entries}" "" "" ${file_type_arg})
	if(DEFINED _arg_filetype_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unkown keywords for FILETYPE: ${_arg_filetype_UNPARSED_ARGUMENTS}")
	endif()

	set(${out_filetype_list} "")
	foreach(entry ${valid_entries})
		if(_arg_filetype_${entry})
			list(APPEND ${out_filetype_list} ${entry})
		endif()
	endforeach()

	set(${out_filetype_list} "${${out_filetype_list}}" PARENT_SCOPE)
endfunction()

# Starts SBOM generation. Call sbom_add() and friends afterwards. End with sbom_finalize(). Input
# files allow having variables and generator expressions.
function(sbom_generate)
	set(oneValueArgs
		OUTPUT
		NAMESPACE
		PACKAGE_NAME
		PACKAGE_VERSION
		PACKAGE_FILENAME
		PACKAGE_DOWNLOAD
		PACKAGE_URL
		PACKAGE_LICENSE
		PACKAGE_COPYRIGHT
	)
	set(multiValueArgs CREATOR PACKAGE_NOTES PACKAGE_PURPOSE)
	cmake_parse_arguments(
		_arg_sbom_gen "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN}
	)

	if(_arg_sbom_gen_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown arguments: ${_arg_sbom_gen_UNPARSED_ARGUMENTS}")
	endif()

	if(NOT DEFINED GIT_VERSION)
		version_extract()
	endif()

	if(NOT DEFINED _arg_sbom_gen_CREATOR)
		message(FATAL_ERROR "Missing required argument CREATOR.")
	endif()

	cmake_parse_arguments(_arg_sbom_gen_CREATOR "" "PERSON;ORGANIZATION;EMAIL" "" ${_arg_sbom_gen_CREATOR})
	if(_arg_sbom_gen_CREATOR_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown subarguments for CREATOR: ${_arg_sbom_gen_CREATOR_UNPARSED_ARGUMENTS}.")
	endif()
	if((NOT DEFINED _arg_sbom_gen_CREATOR_PERSON) AND (NOT DEFINED _arg_sbom_gen_CREATOR_ORGANIZATION))
		message(FATAL_ERROR "Missing <PERSON|ORGANIZATION> <name> for argument CREATOR.")
	elseif(DEFINED _arg_sbom_gen_CREATOR_PERSON AND DEFINED _arg_sbom_gen_CREATOR_ORGANIZATION)
		message(FATAL_ERROR "Specify either PERSON or ORGANIZATION, not both.")
	endif()

	if(NOT DEFINED _arg_sbom_gen_PACKAGE_LICENSE)
		message(FATAL_ERROR "Missing required argument PACKAGE_LICENSE.")
	endif()

	if(NOT DEFINED _arg_sbom_gen_PACKAGE_NAME)
		set(_arg_sbom_gen_PACKAGE_NAME ${PROJECT_NAME})
	endif()

	if(NOT DEFINED _arg_sbom_gen_PACKAGE_VERSION)
		set(_arg_sbom_gen_PACKAGE_VERSION ${GIT_VERSION})
	endif()

	if(NOT DEFINED _arg_sbom_gen_PACKAGE_FILENAME)
		set(_arg_sbom_gen_PACKAGE_FILENAME "${_arg_sbom_gen_PACKAGE_NAME}-${_arg_sbom_gen_PACKAGE_VERSION}.zip")
	endif()

	if(NOT DEFINED _arg_sbom_gen_PACKAGE_DOWNLOAD)
		# if not defined, the creator made no attempt to specify a download location
		set(_arg_sbom_gen_PACKAGE_DOWNLOAD "NOASSERTION")
	else()
		cmake_parse_arguments(_arg_sbom_gen_PACKAGE_DOWNLOAD "NONE;NOASSERTION" "" "" ${_arg_sbom_gen_PACKAGE_DOWNLOAD})
		if(_arg_sbom_gen_PACKAGE_DOWNLOAD_NONE)
			set(_arg_sbom_gen_PACKAGE_DOWNLOAD "NONE")
		elseif(_arg_sbom_gen_PACKAGE_DOWNLOAD_NOASSERTION)
			set(_arg_sbom_gen_PACKAGE_DOWNLOAD "NOASSERTION")
		endif()
	endif()

	if(NOT DEFINED _arg_sbom_gen_PACKAGE_URL)
		if(NOT DEFINED _arg_sbom_gen_NAMESPACE)
			message(FATAL_ERROR "Specify NAMESPACE when PACKAGE_URL is omitted.")
		endif()
	endif()

	string(TIMESTAMP NOW_UTC UTC)

	if(NOT DEFINED _arg_sbom_gen_PACKAGE_COPYRIGHT)
		string(TIMESTAMP NOW_YEAR "%Y" UTC)

		if(DEFINED _arg_sbom_gen_CREATOR_PERSON)
			set(_arg_sbom_gen_PACKAGE_COPYRIGHT "${NOW_YEAR} ${_arg_sbom_gen_CREATOR_PERSON}")
		elseif(DEFINED _arg_sbom_gen_CREATOR_ORGANIZATION)
			set(_arg_sbom_gen_PACKAGE_COPYRIGHT "${NOW_YEAR} ${_arg_sbom_gen_CREATOR_ORGANIZATION}")
		else()
			set(_arg_sbom_gen_PACKAGE_COPYRIGHT "NOASSERTION")
		endif()
	else()
		cmake_parse_arguments(_arg_sbom_gen_PACKAGE_COPYRIGHT "NONE;NOASSERTION" "" "" ${_arg_sbom_gen_PACKAGE_COPYRIGHT})
		if(_arg_sbom_gen_PACKAGE_COPYRIGHT_NONE)
			set(_arg_sbom_gen_PACKAGE_COPYRIGHT "NONE")
		elseif(_arg_sbom_gen_PACKAGE_COPYRIGHT_NOASSERTION)
			set(_arg_sbom_gen_PACKAGE_COPYRIGHT "NOASSERTION")
		endif()
	endif()

	if(DEFINED _arg_sbom_gen_PACKAGE_NOTES)
		_sbom_parse_package_notes("${_arg_sbom_gen_PACKAGE_NOTES}" _arg_sbom_gen_PACKAGE_SUMMARY
																   _arg_sbom_gen_PACKAGE_DESC
																   __unused__)
		unset(__unused__)
	endif()

	if(DEFINED _arg_sbom_gen_PACKAGE_PURPOSE)
		_sbom_parse_package_purpose("${_arg_sbom_gen_PACKAGE_PURPOSE}" _arg_sbom_gen_PACKAGE_PURPOSE)
	endif()

	if(NOT DEFINED _arg_sbom_gen_OUTPUT)
		set(_arg_sbom_gen_OUTPUT "./${CMAKE_INSTALL_DATAROOTDIR}/${_arg_sbom_gen_PACKAGE_NAME}-sbom-${GIT_VERSION_PATH}.spdx")
	endif()

	if(NOT DEFINED _arg_sbom_gen_NAMESPACE)
		if((NOT DEFINED _arg_sbom_gen_PACKAGE_URL) OR (_arg_sbom_gen_PACKAGE_URL STREQUAL "NONE") OR (_arg_sbom_gen_PACKAGE_URL STREQUAL "NOASSERTION"))
			message(FATAL_ERROR "Specifiy PACKAGE_URL <url> when NAMESPACE is omitted.")
		endif()
		set(_arg_sbom_gen_NAMESPACE "${_arg_sbom_gen_PACKAGE_URL}/spdxdocs/${_arg_sbom_gen_PACKAGE_NAME}-${_arg_sbom_gen_PACKAGE_VERSION}")
	endif()

	# remove special characters from package name and replace with -
	string(REGEX REPLACE "[^A-Za-z0-9.]+" "-" _arg_sbom_gen_PACKAGE_NAME "${_arg_sbom_gen_PACKAGE_NAME}")
	# strip - from end of string
	string(REGEX REPLACE "-+$" "" _arg_sbom_gen_PACKAGE_NAME "${_arg_sbom_gen_PACKAGE_NAME}")

	# Prevent collision with other generated SPDXID with -[0-9]+ suffix, by removing -.
	string(REGEX REPLACE "-([0-9]+)$" "\\1" _arg_sbom_gen_PACKAGE_NAME "${_arg_sbom_gen_PACKAGE_NAME}")

	set(SBOM_FILENAME "${_arg_sbom_gen_OUTPUT}" PARENT_SCOPE)
	set(SBOM_BINARY_DIR "${PROJECT_BINARY_DIR}/sbom")
	set(SBOM_SNIPPET_DIR "${SBOM_BINARY_DIR}/sbom-src/$<CONFIG>")
	set_property(GLOBAL PROPERTY SBOM_FILENAME "${_arg_sbom_gen_OUTPUT}")
	set_property(GLOBAL PROPERTY SBOM_BINARY_DIR "${SBOM_BINARY_DIR}")
	set_property(GLOBAL PROPERTY SBOM_SNIPPET_DIR "${SBOM_SNIPPET_DIR}")
	set_property(GLOBAL PROPERTY sbom_package_spdxid "${_arg_sbom_gen_PACKAGE_NAME}")
	set_property(GLOBAL PROPERTY sbom_package_license "${_arg_sbom_gen_PACKAGE_LICENSE}")
	set_property(GLOBAL PROPERTY sbom_package_copyright "${_arg_sbom_gen_PACKAGE_COPYRIGHT}")
	set_property(GLOBAL PROPERTY sbom_spdxids 0)

	#REFAC(>=3.20): Use cmake_path() instead of get_filename_component().
	if(CMAKE_VERSION VERSION_GREATER_EQUAL 3.20)
		cmake_path(GET _arg_sbom_gen_OUTPUT FILENAME doc_name)
	else()
		get_filename_component(doc_name "${_arg_sbom_gen_OUTPUT}" NAME_WLE)
	endif()

	file(MAKE_DIRECTORY ${SBOM_BINARY_DIR})

	# collect all sbom install instructions in a separate file.
	# To keep things debuggable, we don't want to mix the sbom instructions with the rest of the install instructions.
	# Will be added via add_subdirectory() to the main project.
	file(WRITE ${SBOM_BINARY_DIR}/CMakeLists.txt "set(SBOM_SNIPPET_DIR \"${SBOM_SNIPPET_DIR}\")\n")

	set(_sbom_intermediate_file "$<CONFIG>/sbom.spdx.in")
	set(_sbom_document_template "SPDXRef-DOCUMENT.spdx.in")
	set(_sbom_export_path "${_arg_sbom_gen_OUTPUT}")

	if(NOT IS_ABSOLUTE "${_arg_sbom_gen_OUTPUT}")
		set(_sbom_export_path "\${CMAKE_INSTALL_PREFIX}/${_arg_sbom_gen_OUTPUT}")
	endif()

	_sbom_generate_document_template()
	set(SBOM_LAST_SPDXID "SPDXRef-${_arg_sbom_gen_PACKAGE_NAME}" PARENT_SCOPE)

	_sbom_append_sbom_snippet("setup.cmake")
	file(GENERATE
		OUTPUT ${SBOM_SNIPPET_DIR}/setup.cmake
		CONTENT "
set(SBOM_EXPORT_FILENAME \"${_sbom_export_path}\")
set(SBOM_BINARY_DIR \"${SBOM_BINARY_DIR}\")
set(SBOM_SNIPPET_DIR \"${SBOM_SNIPPET_DIR}\")
set(SBOM_DOCUMENT_TEMPLATE \"${_sbom_document_template}\")
set(SBOM_EXT_DOCS)
message(STATUS \"Installing: \${SBOM_EXPORT_FILENAME}\")

# this file is used to collect all SPDX entries before final export
set(SBOM_INTERMEDIATE_FILE \"\${SBOM_BINARY_DIR}/sbom-build/${_sbom_intermediate_file}\")
file(WRITE \${SBOM_INTERMEDIATE_FILE} \"\")

file(READ \"\${SBOM_SNIPPET_DIR}/\${SBOM_DOCUMENT_TEMPLATE}\" _f_contents)
file(APPEND \"\${SBOM_INTERMEDIATE_FILE}\" \"\${_f_contents}\")

set(SBOM_VERIFICATION_CODES \"\")
"
	)
endfunction()

# Finalize the generated SBOM. Call after sbom_generate() and other SBOM populating commands.
function(sbom_finalize)
	get_property(_sbom GLOBAL PROPERTY SBOM_FILENAME)
	get_property(_sbom_binary_dir GLOBAL PROPERTY SBOM_BINARY_DIR)
	get_property(_sbom_snippet_dir GLOBAL PROPERTY SBOM_SNIPPET_DIR)
	get_property(_sbom_project GLOBAL PROPERTY sbom_package_spdxid)

	if("${_sbom_project}" STREQUAL "")
		message(FATAL_ERROR "Call sbom_generate() first")
	endif()

	_sbom_append_sbom_snippet("finalize.cmake")
	file(GENERATE
		OUTPUT ${_sbom_snippet_dir}/finalize.cmake
		CONTENT
"message(STATUS \"Finalizing: \${SBOM_EXPORT_FILENAME}\")
list(SORT SBOM_VERIFICATION_CODES)
string(REPLACE \";\" \"\" SBOM_VERIFICATION_CODES \"\${SBOM_VERIFICATION_CODES}\")
string(TIMESTAMP SBOM_CREATE_DATE UTC)
if(NOT \"\${SBOM_EXT_DOCS}\" STREQUAL \"\")
	string(REPLACE \";\" \"\\n\" SBOM_EXT_DOCS \"\${SBOM_EXT_DOCS}\")
	string(APPEND SBOM_EXT_DOCS \"\\n\")
endif()
file(WRITE \"\${SBOM_BINARY_DIR}/sbom-build/$<CONFIG>/verification.txt\" \"\${SBOM_VERIFICATION_CODES}\")
file(SHA1 \"\${SBOM_BINARY_DIR}/sbom-build/$<CONFIG>/verification.txt\" SBOM_VERIFICATION_CODE)
configure_file(\"\${SBOM_INTERMEDIATE_FILE}\" \"\${SBOM_EXPORT_FILENAME}\")
"
	)

	# using a build dir will generate a seperate cmake_install.cmake file
	# which helps with debugging
	add_subdirectory(${_sbom_binary_dir} ${_sbom_binary_dir}/sbom-build )

	# Mark finalized.
	set(SBOM_FILENAME "${_sbom}" PARENT_SCOPE)
	set_property(GLOBAL PROPERTY sbom_package_spdxid "")
endfunction()

macro(_sbom_builder_is_setup)
	get_property(_sbom_project GLOBAL PROPERTY sbom_package_spdxid)

	if("${_sbom_project}" STREQUAL "")
		message(FATAL_ERROR "Call sbom_generate() first")
	endif()
endmacro()

function(_sbom_add_pkg_content PATH)
	set(options OPTIONAL FILE DIR)
	set(oneValueArgs SPDXID
					 RELATIONSHIP
					 COPYRIGHT
					 COMMENT
					 NOTICE
					 CONTRIBUTORS
					 ATTRIBUTION
					 )
	set(multiValueArgs FILETYPE CHECKSUM LICENSE)
	cmake_parse_arguments(_arg_add_pkg_content "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

	_sbom_builder_is_setup()

	if(_arg_add_pkg_content_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown arguments: ${_arg_add_pkg_content_UNPARSED_ARGUMENTS}")
	endif()

	sbom_spdxid(
		VARIABLE _arg_add_pkg_content_SPDXID
		CHECK "${_arg_add_pkg_content_SPDXID}"
		HINTS "SPDXRef-${PATH}"
	)
	set(SBOM_LAST_SPDXID "${_arg_add_pkg_content_SPDXID}" PARENT_SCOPE)

	set(_fields "")

	set(_arg_add_pkg_content_LICENSE_DECLARED "NOASSERTION")
	if(NOT DEFINED _arg_add_pkg_content_LICENSE)
		get_property(_sbom_package_license GLOBAL PROPERTY sbom_package_license)
		set(_arg_add_pkg_content_LICENSE "${_sbom_package_license}")
	endif()
	_sbom_parse_license("CONCLUDED;${_arg_add_pkg_content_LICENSE}" _arg_add_pkg_content_LICENSE_CONCLUDED _arg_add_pkg_content_LICENSE_DECLARED _arg_add_pkg_content_LICENSE_COMMENT)
	string(APPEND _fields "\nLicenseConcluded: ${_arg_add_pkg_content_LICENSE_CONCLUDED}")
	if(DEFINED _arg_add_pkg_content_LICENSE_COMMENT)
		string(APPEND _fields "\nLicenseComments: ${_arg_add_pkg_content_LICENSE_COMMENT}")
	endif()

	if(DEFINED _arg_add_pkg_content_FILETYPE)
		_sbom_parse_filetype("${_arg_add_pkg_content_FILETYPE}" _arg_add_pkg_content_FILETYPE)
		foreach(_filetype ${_arg_add_pkg_content_FILETYPE})
			string(APPEND _fields "\nFileType: ${_filetype}")
		endforeach()
	endif()

	if(DEFINED _arg_add_pkg_content_CHECKSUM)
		set(_hash_algo "SHA1;SHA256") # SHA1 is always required by SPDX, SHA256 required by TR-03183
		set(_supported_algorithms "MD5;SHA224;SHA384;SHA512;SHA3-256;SHA3-384;SHA3-512")
		foreach(_checksum ${_arg_add_pkg_content_CHECKSUM})
			if("${_checksum}" IN_LIST _supported_algorithms)
				list(APPEND _hash_algo "${_checksum}")
			else()
				message(FATAL_ERROR "Unsupported checksum algorithm: ${_checksum}")
			endif()
		endforeach()
	endif()

	if(NOT DEFINED _arg_add_pkg_content_COPYRIGHT)
		get_property(_sbom_package_copyright GLOBAL PROPERTY sbom_package_copyright)
		set(_arg_add_pkg_content_COPYRIGHT "${_sbom_package_copyright}")
	endif()
	string(APPEND _fields "\nFileCopyrightText: ${_arg_add_pkg_content_COPYRIGHT}")

	if(DEFINED _arg_add_pkg_content_COMMENT)
		string(APPEND _fields "\nComment: ${_arg_add_pkg_content_COMMENT}")
	endif()

	if(DEFINED _arg_add_pkg_content_NOTICE)
		string(APPEND _fields "\nFileNotice: ${_arg_add_pkg_content_NOTICE}")
	endif()

	if(DEFINED _arg_add_pkg_content_CONTRIBUTORS)
		foreach(_contributor ${_arg_add_pkg_content_CONTRIBUTORS})
			string(APPEND _fields "\nFileContributor: ${_contributor}")
		endforeach()
	endif()

	if(DEFINED _arg_add_pkg_content_ATTRIBUTION)
		foreach(_attribution ${_arg_add_pkg_content_ATTRIBUTION})
			string(APPEND _fields "\nFileAttributionText: ${_attribution}")
		endforeach()
	endif()

	if(NOT DEFINED _arg_add_pkg_content_RELATIONSHIP)
		set(_arg_add_pkg_content_RELATIONSHIP "SPDXRef-${_sbom_project} CONTAINS ${_arg_add_pkg_content_SPDXID}")
	else()
		string(REPLACE "@SBOM_LAST_SPDXID@" "${_arg_add_pkg_content_SPDXID}" _arg_add_pkg_content_RELATIONSHIP "${_arg_add_pkg_content_RELATIONSHIP}")
	endif()

	get_property(_sbom_snippet_dir GLOBAL PROPERTY SBOM_SNIPPET_DIR)

	_sbom_append_sbom_snippet("${_arg_add_pkg_content_SPDXID}.cmake")
	file(
		GENERATE
		OUTPUT ${_sbom_snippet_dir}/${_arg_add_pkg_content_SPDXID}.cmake
		CONTENT
		"
cmake_policy(SET CMP0011 NEW)
cmake_policy(SET CMP0012 NEW)

set(ADDING_DIR ${_arg_add_pkg_content_DIR})

set(_files \"\")
if(NOT ADDING_DIR)
	set(_files \"./${PATH}\")
else()
	file(GLOB_RECURSE _files
		LIST_DIRECTORIES false RELATIVE \"\${CMAKE_INSTALL_PREFIX}\"
		\"\${CMAKE_INSTALL_PREFIX}/${PATH}/*\"
)
endif()

if((NOT ADDING_DIR) AND (NOT EXISTS \${CMAKE_INSTALL_PREFIX}/${PATH}))
	if(NOT ${_arg_add_pkg_content_OPTIONAL})
		message(FATAL_ERROR \"Cannot find ./${PATH}\")
	endif()
else()
	set(_count 0)
	set(_rel \"${_arg_add_pkg_content_RELATIONSHIP}\")
	set(_id \"${_arg_add_pkg_content_SPDXID}\")
	foreach(_f IN LISTS _files)
		if(ADDING_DIR)
			set(_rel \"${_arg_add_pkg_content_RELATIONSHIP}-\${_count}\")
			set(_id \"${_arg_add_pkg_content_SPDXID}-\${_count}\")
			math(EXPR _count \"\${_count} + 1\")
		endif()
		set(_checksum_fields \"\")
		foreach(_algo ${_hash_algo})
			file(\${_algo} \${CMAKE_INSTALL_PREFIX}/\${_f} _hash)
			if(\"\${_algo}\" STREQUAL \"SHA1\")
				list(APPEND SBOM_VERIFICATION_CODES \${_hash})
			endif()
			string(APPEND _checksum_fields \"\\nFileChecksum: \${_algo}: \${_hash}\")
		endforeach()
		file(APPEND \"\${SBOM_INTERMEDIATE_FILE}\"
\"
FileName: ./\${_f}
SPDXID: \${_id}\
${_fields}\
\${_checksum_fields}
Relationship: \${_rel}
\"
	)
	endforeach()
endif()
	"
	)

	set(SBOM_LAST_SPDXID "${SBOM_LAST_SPDXID}" PARENT_SCOPE)
endfunction()

function(sbom_add_directory DIR_PATH)
	_sbom_add_pkg_content("${DIR_PATH}" "DIR" "${ARGN}")
	set(SBOM_LAST_SPDXID "${SBOM_LAST_SPDXID}" PARENT_SCOPE)
endfunction()

function(sbom_add_file FILENAME)
	_sbom_add_pkg_content("${FILENAME}" "${ARGN}")
	set(SBOM_LAST_SPDXID "${SBOM_LAST_SPDXID}" PARENT_SCOPE)
endfunction()

# Append a target output to the SBOM. Use this after calling sbom_generate().
function(sbom_add_target NAME)
	_sbom_builder_is_setup()

	get_target_property(_type ${NAME} TYPE)

	if("${_type}" STREQUAL "EXECUTABLE")
		sbom_add_file(${CMAKE_INSTALL_BINDIR}/$<TARGET_FILE_NAME:${NAME}>
			FILETYPE BINARY ${ARGN}
		)
	elseif("${_type}" STREQUAL "STATIC_LIBRARY")
		sbom_add_file(${CMAKE_INSTALL_LIBDIR}/$<TARGET_FILE_NAME:${NAME}>
			FILETYPE BINARY ${ARGN}
		)
	elseif("${_type}" STREQUAL "SHARED_LIBRARY")
		if(WIN32)
			sbom_add_file(
				${CMAKE_INSTALL_BINDIR}/$<TARGET_FILE_NAME:${NAME}>
				FILETYPE BINARY ${ARGN}
			)
			sbom_add_file(
				${CMAKE_INSTALL_LIBDIR}/$<TARGET_LINKER_FILE_NAME:${NAME}>
				FILETYPE BINARY OPTIONAL ${ARGN}
			)
		else()
			sbom_add_file(
				${CMAKE_INSTALL_LIBDIR}/$<TARGET_FILE_NAME:${NAME}>
				FILETYPE BINARY ${ARGN}
			)
		endif()
	else()
		message(FATAL_ERROR "Unsupported target type ${_type}")
	endif()

	set(SBOM_LAST_SPDXID "${SBOM_LAST_SPDXID}" PARENT_SCOPE)
endfunction()

# Append a package (without files) to the SBOM. Use this after calling sbom_generate().
function(sbom_add_package NAME)
	set(oneValueArgs
		SPDXID
		RELATIONSHIP
		VERSION
		FILENAME
		DOWNLOAD
		URL
		SOURCE_INFO
		COPYRIGHT
	)
	set(multiValueArgs
		SUPPLIER
		ORIGINATOR
		CHECKSUM
		EXTREF
		LICENSE
		NOTES
		ATTRIBUTION
		PURPOSE
		DATE
	)
	cmake_parse_arguments(
		_arg_add_pkg "" "${oneValueArgs}" "${multiValueArgs}" ${ARGN}
	)

	_sbom_builder_is_setup()

	if(_arg_add_pkg_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown arguments: ${_arg_add_pkg_UNPARSED_ARGUMENTS}")
	endif()

	sbom_spdxid(
		VARIABLE _arg_add_pkg_SPDXID
		CHECK "${_arg_add_pkg_SPDXID}"
		HINTS "SPDXRef-${NAME}"
	)

	set(SBOM_LAST_SPDXID ${_arg_add_pkg_SPDXID} PARENT_SCOPE)

	set(_fields "PackageName: ${NAME}\nSPDXID: ${_arg_add_pkg_SPDXID}")

	set(_arg_add_pkg_LICENSE_DECLARED "NOASSERTION")
	if(NOT DEFINED _arg_add_pkg_LICENSE)
		message(FATAL_ERROR "Missing LICENSE argument for package ${NAME}.")
	endif()
	_sbom_parse_license("CONCLUDED;${_arg_add_pkg_LICENSE}" _arg_add_pkg_LICENSE_CONCLUDED _arg_add_pkg_LICENSE_DECLARED _arg_add_pkg_LICENSE_COMMENT)
	string(APPEND _fields "\nPackageLicenseConcluded: ${_arg_add_pkg_LICENSE_CONCLUDED}\nPackageLicenseDeclared: ${_arg_add_pkg_LICENSE_DECLARED}")
	if(DEFINED _arg_add_pkg_LICENSE_COMMENT)
		string(APPEND _fields "\nPackageLicenseComments: ${_arg_add_pkg_LICENSE_COMMENT}")
	endif()

	if(NOT DEFINED _arg_add_pkg_VERSION)
		message(FATAL_ERROR "Missing VERSION argument for package ${NAME}.")
	endif()
	string(APPEND _fields "\nPackageVersion: ${_arg_add_pkg_VERSION}")

	if(NOT DEFINED _arg_add_pkg_SUPPLIER)
		message(FATAL_ERROR "Missing SUPPLIER argument for package ${NAME}.")
	endif()
	set(_supplier_field_txt "")
	_sbom_parse_package_supplier("${_arg_add_pkg_SUPPLIER}" _arg_add_pkg_SUPPLIER_TYPE _arg_add_pkg_SUPPLIER_NAME _arg_add_pkg_SUPPLIER_EMAIL)
	if("${_arg_add_pkg_SUPPLIER_TYPE}" STREQUAL "NOASSERTION")
		message(FATAL_ERROR "SUPPLIER must be a PERSON or ORGANIZATION.")
	else()
		set(_supplier_field_txt "PackageSupplier: ${_arg_add_pkg_SUPPLIER_TYPE} ${_arg_add_pkg_SUPPLIER_NAME}")
		if(DEFINED _arg_add_pkg_SUPPLIER_EMAIL)
			set(_supplier_field_txt "${_supplier_field_txt} (${_arg_add_pkg_SUPPLIER_EMAIL})")
		endif()
	endif()
	string(APPEND _fields "\n${_supplier_field_txt}")

	if(DEFINED _arg_add_pkg_FILENAME)
		string(APPEND _fields "\nPackageFileName: ${_arg_add_pkg_FILENAME}")
	endif()

	if(DEFINED _arg_add_pkg_ORIGINATOR)
		set(_originator_field_txt "")
		_sbom_parse_package_supplier("${_arg_add_pkg_ORIGINATOR}" _arg_add_pkg_ORIGINATOR_TYPE _arg_add_pkg_ORIGINATOR_NAME _arg_add_pkg_ORIGINATOR_EMAIL)
		if("${_arg_add_pkg_ORIGINATOR_TYPE}" STREQUAL "NOASSERTION")
			set(_originator_field_txt "PackageOriginator: NOASSERTION")
		else()
			set(_originator_field_txt "PackageOriginator: ${_arg_add_pkg_ORIGINATOR_TYPE} ${_arg_add_pkg_ORIGINATOR_NAME}")
			if(DEFINED _arg_add_pkg_ORIGINATOR_EMAIL)
				set(_originator_field_txt "${_originator_field_txt} (${_arg_add_pkg_ORIGINATOR_EMAIL})")
			endif()
		endif()
		string(APPEND _fields "\n${_originator_field_txt}")
	endif()

	if(NOT DEFINED _arg_add_pkg_DOWNLOAD)
		set(_arg_add_pkg_DOWNLOAD "NOASSERTION")
	endif()
	string(APPEND _fields "\nPackageDownloadLocation: ${_arg_add_pkg_DOWNLOAD}")

	if(DEFINED _arg_add_pkg_CHECKSUM)
		set(_algo TRUE) #first string is the algorithm, second is the checksum
		set(_checksum_field_txt "")
		foreach(_checksum IN LISTS _arg_add_pkg_CHECKSUM)
			if(_algo)
				set(_algo FALSE)
				set(_checksum_field_txt "${_checksum_field_txt}\nPackageChecksum: ${_checksum}:")
			else()
				set(_algo TRUE)
				set(_checksum_field_txt "${_checksum_field_txt} ${_checksum}")
			endif()
		endforeach()
		string(APPEND _fields "${_checksum_field_txt}")
	endif()

	if(DEFINED _arg_add_pkg_URL)
		string(APPEND _fields "\nPackageHomePage: ${_arg_add_pkg_URL}")
	endif()

	if(DEFINED _arg_add_pkg_SOURCE_INFO)
		string(APPEND _fields "\nPackageSourceInfo: ${_arg_add_pkg_URL}")
	endif()

	if(NOT DEFINED _arg_add_pkg_COPYRIGHT)
		set(_arg_add_pkg_COPYRIGHT "NOASSERTION")
	endif()
	string(APPEND _fields "\nPackageCopyrightText: ${_arg_add_pkg_COPYRIGHT}")

	if(DEFINED _arg_add_pkg_NOTES)
		_sbom_parse_package_notes("${_arg_add_pkg_NOTES}" _arg_add_pkg_SUMMARY _arg_add_pkg_DESC _arg_add_pkg_COMMENT)
		if(DEFINED _arg_add_pkg_SUMMARY)
			string(APPEND _fields "\nPackageSummary: <text>${_arg_add_pkg_SUMMARY}</text>")
		endif()
		if(DEFINED _arg_add_pkg_DESC)
			string(APPEND _fields "\nPackageDescription: <text>${_arg_add_pkg_DESC}</text>")
		endif()
		if(DEFINED _arg_add_pkg_COMMENT)
			string(APPEND _fields "\nPackageComment: <text>${_arg_add_pkg_COMMENT}</text>")
		endif()
	endif()

	foreach(_ref IN LISTS _arg_add_pkg_EXTREF)
		string(APPEND _fields "\nExternalRef: ${_ref}")
	endforeach()

	if(DEFINED _arg_add_pkg_ATTRIBUTION)
		foreach(_attr IN LISTS _arg_add_pkg_ATTRIBUTION)
			string(APPEND _fields "\nPackageAttributionText: ${_attr}")
		endforeach()
	endif()

	if(DEFINED _arg_add_pkg_PURPOSE)
		_sbom_parse_package_purpose("${_arg_add_pkg_PURPOSE}" _arg_add_pkg_PURPOSE)
		foreach(_purpose IN LISTS _arg_add_pkg_PURPOSE)
			string(APPEND _fields "\nPrimaryPackagePurpose: ${_purpose}")
		endforeach()
	endif()

	if(DEFINED _arg_add_pkg_DATE)
		_sbom_parse_dates("${_arg_add_pkg_DATE}" _arg_add_pkg_date_Build _arg_add_pkg_date_Rel _arg_add_pkg_date_VU)
		if(DEFINED _arg_add_pkg_date_Build)
			string(APPEND _fields "\nBuildDate: ${_arg_add_pkg_date_Build}")
		endif()
		if(DEFINED _arg_add_pkg_date_Rel)
			string(APPEND _fields "\nReleaseDate: ${_arg_add_pkg_date_Rel}")
		endif()
		if(DEFINED _arg_add_pkg_date_VU)
			string(APPEND _fields "\nValidUntilDate: ${_arg_add_pkg_date_VU}")
		endif()
	endif()

	if(NOT DEFINED _arg_add_pkg_RELATIONSHIP)
		set(_arg_add_pkg_RELATIONSHIP "SPDXRef-${_sbom_project} DEPENDS_ON ${_arg_add_pkg_SPDXID}")
	else()
		string(REPLACE "@SBOM_LAST_SPDXID@" "${_arg_add_pkg_SPDXID}" _arg_add_pkg_RELATIONSHIP "${_arg_add_pkg_RELATIONSHIP}")
	endif()
	string(APPEND _fields "\nRelationship: ${_arg_add_pkg_RELATIONSHIP}\nRelationship: ${_arg_add_pkg_SPDXID} CONTAINS NOASSERTION")

	get_property(_sbom_snippet_dir GLOBAL PROPERTY SBOM_SNIPPET_DIR)

	_sbom_append_sbom_snippet("${_arg_add_pkg_SPDXID}.cmake")
	file(
		GENERATE
		OUTPUT ${_sbom_snippet_dir}/${_arg_add_pkg_SPDXID}.cmake
		CONTENT
		"
			file(APPEND \"\${SBOM_INTERMEDIATE_FILE}\"
\"
${_fields}
\"
			)
			"
	)

	set(SBOM_LAST_SPDXID "${SBOM_LAST_SPDXID}" PARENT_SCOPE)
endfunction()

# Add a reference to a package in an external file.
function(sbom_add_external ID PATH)
	set(oneValueArgs RENAME SPDXID RELATIONSHIP)
	cmake_parse_arguments(
		_arg_add_extern "" "${oneValueArgs}" "" ${ARGN}
	)

	_sbom_builder_is_setup()

	if(_arg_add_extern_UNPARSED_ARGUMENTS)
		message(FATAL_ERROR "Unknown arguments: ${_arg_add_extern_UNPARSED_ARGUMENTS}")
	endif()

	if("${_arg_add_extern_SPDXID}" STREQUAL "")
		get_property(_spdxids GLOBAL PROPERTY sbom_spdxids)
		set(_arg_add_extern_SPDXID "DocumentRef-${_spdxids}")
		math(EXPR _spdxids "${_spdxids} + 1")
		set_property(GLOBAL PROPERTY sbom_spdxids "${_spdxids}")
	endif()

	if(NOT "${_arg_add_extern_SPDXID}" MATCHES "^DocumentRef-[-a-zA-Z0-9]+$")
		message(FATAL_ERROR "Invalid DocumentRef \"${_arg_add_extern_SPDXID}\"")
	endif()

	set(SBOM_LAST_SPDXID "${_arg_add_extern_SPDXID}" PARENT_SCOPE)

	get_filename_component(sbom_dir "${_sbom}" DIRECTORY)

	if("${_arg_add_extern_RELATIONSHIP}" STREQUAL "")
		set(_arg_add_extern_RELATIONSHIP
			"SPDXRef-${_sbom_project} DEPENDS_ON ${_arg_add_extern_SPDXID}:${ID}"
		)
	else()
		string(REPLACE "@SBOM_LAST_SPDXID@" "${_arg_add_extern_SPDXID}"
			_arg_add_extern_RELATIONSHIP "${_arg_add_extern_RELATIONSHIP}"
		)
	endif()

	get_property(_sbom_snippet_dir GLOBAL PROPERTY SBOM_SNIPPET_DIR)

	_sbom_append_sbom_snippet("${_arg_add_extern_SPDXID}.cmake")
	file(
		GENERATE
		OUTPUT ${_sbom_snippet_dir}/${_arg_add_extern_SPDXID}.cmake
		CONTENT
"file(SHA1 \"${PATH}\" ext_sha1)
file(READ \"${PATH}\" ext_content)
if(\"${_arg_add_extern_RENAME}\" STREQUAL \"\")
	get_filename_component(ext_name \"${PATH}\" NAME)
	file(WRITE \"${sbom_dir}/\${ext_name}\" \"\${ext_content}\")
else()
	file(WRITE \"${sbom_dir}/${_arg_add_extern_RENAME}\" \"\${ext_content}\")
endif()

if(NOT \"\${ext_content}\" MATCHES \"[\\r\\n]DocumentNamespace:\")
	message(FATAL_ERROR \"Missing DocumentNamespace in ${PATH}\")
endif()

string(REGEX REPLACE
	\"^.*[\\r\\n]DocumentNamespace:[ \\t]*([^#\\r\\n]*).*$\" \"\\\\1\" ext_ns \"\${ext_content}\")

list(APPEND SBOM_EXT_DOCS \"ExternalDocumentRef: ${_arg_add_extern_SPDXID} \${ext_ns} SHA1: \${ext_sha1}\")

file(APPEND \"\${SBOM_INTERMEDIATE_FILE}\" \"Relationship: ${_arg_add_extern_RELATIONSHIP}\\n\")
"
	)
endfunction()
