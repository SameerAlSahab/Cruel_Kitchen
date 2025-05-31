#!/bin/bash
# cruel_kitchen.sh 

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


INPUT_DIR="$SCRIPT_DIR/input_apk"
OUTPUT_DIR="$SCRIPT_DIR/output_apk"
WORK_ROOT="$SCRIPT_DIR/workspace"
PATCHES_DIR="$SCRIPT_DIR/resources/patches"
APKTOOL_JAR="$SCRIPT_DIR/external/apktool/apktool.jar"
ANDROID15_MARKER="debian.mime.types"
RES_DIR="$SCRIPT_DIR/framework_res"

# SDK Version options (Android versions)
SDK_VERSIONS=(
    [23]="Android 6.0 (Marshmallow)"
    [24]="Android 7.0 (Nougat)"
    [25]="Android 7.1 (Nougat)"
    [26]="Android 8.0 (Oreo)"
    [27]="Android 8.1 (Oreo)"
    [28]="Android 9.0 (Pie)"
    [29]="Android 10 (Q)"
    [30]="Android 11 (R)"
    [31]="Android 12 (S)"
    [32]="Android 12L (S_V2)"
    [33]="Android 13 (Tiramisu)"
    [34]="Android 14 (UpsideDownCake)"
    [35]="Android 15 (VanillaIceCream)"
	[36]="Android 16 (Baklava)"
)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# State variables
DECOMPILED_APK=""
SELECTED_PATCH_SET=""
CURRENT_SDK=35  #DEFAULT SDK

# Error handling
trap 'echo -e "${RED}Script interrupted! Cleaning up...${NC}"; cleanup; exit 1' INT TERM

verify_environment() {
    echo -e "${GREEN}[+] Verifying environment...${NC}"
    
    # Check apktool
    if [[ ! -f "$APKTOOL_JAR" ]]; then
        echo -e "${RED}ERROR: apktool.jar not found at:${NC}"
        echo -e "  ${YELLOW}$APKTOOL_JAR${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ apktool.jar found${NC}"

    # Create directories
    mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORK_ROOT" "$PATCHES_DIR"
    return 0
}

show_header() {
    clear
    echo -e "${MAGENTA}"
    echo "________________________________________________"
    echo "    CRUEL_KITCHEN V1.1.8  @SameerAlSahab"
    echo "________________________________________________"
    echo -e "${NC}"
    echo -e "${CYAN}Current state:${NC}"
    echo -e "  Decompiled APK: ${YELLOW}${DECOMPILED_APK:-None}${NC}"
    echo -e "  Patch set: ${YELLOW}${SELECTED_PATCH_SET:-None}${NC}"
    echo -e "  SDK version: ${YELLOW}${CURRENT_SDK} (${SDK_VERSIONS[$CURRENT_SDK]})${NC}"
    echo
}

show_menu() {
    echo -e "${BLUE}Main Menu:${NC}"
    echo -e "  1) Decompile APK/JAR                           6) Change SDK version"
    echo -e "  2) Select patch set                            7) Decompile APK/JAR with framework-res "
    echo -e "  3) Apply patches                               8) Decompile APK/JAR without resources"
    echo -e "  4) Rebuild APK/JAR                             9) Decompile APK/JAR without smali_classes"
    echo -e "  5) Clean workspace"
    echo -e "  10) Exit"
    echo
}

select_apk() {
    local apks=()
    echo -e "${BLUE}[?] Available APK/JAR files:${NC}"
    
    # Find APK/JAR files
    while IFS= read -r -d $'\0' file; do
        apks+=("$file")
    done < <(find "$INPUT_DIR" -maxdepth 1 \( -iname "*.apk" -o -iname "*.jar" \) -print0)

    # Display selection menu
    if [[ ${#apks[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No APK/JAR files found in $INPUT_DIR${NC}"
        return 1
    fi

    for i in "${!apks[@]}"; do
        echo -e "  ${GREEN}$((i+1))) ${YELLOW}$(basename "${apks[$i]}")${NC}"
    done

    # Get user selection
    while true; do
        read -rp "$(echo -e "${BLUE}Select file (1-${#apks[@]}): ${NC}")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#apks[@]})); then
            SELECTED_APK="${apks[$((choice-1))]}"
            APK_BASENAME="$(basename "$SELECTED_APK")"
            WORK_DIR="$WORK_ROOT/${APK_BASENAME%.*}"
            return 0
        fi
        echo -e "${RED}Invalid selection! Choose between 1-${#apks[@]}${NC}"
    done
}

decompile_apk() {
    [[ -z "$SELECTED_APK" ]] && { echo -e "${RED}No APK selected!${NC}"; return 1; }
    
    echo -e "${GREEN}[+] Decompiling ${YELLOW}$APK_BASENAME${GREEN} with API ${CURRENT_SDK} (${SDK_VERSIONS[$CURRENT_SDK]})...${NC}"
    
    rm -rf "$WORK_DIR" 2>/dev/null
    java -jar "$APKTOOL_JAR" d \
        -api "$CURRENT_SDK" \
        -b \
        -o "$WORK_DIR" \
        "$SELECTED_APK" 2>&1 | tee "$WORK_DIR/decompile.log"
    
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo -e "${RED}ERROR: Decompilation failed!${NC}"
        echo -e "${YELLOW}Check log: $WORK_DIR/decompile.log${NC}"
        return 1
    fi
    
    # Handle Android 15 resources
    if unzip -l "$SELECTED_APK" | grep -q "$ANDROID15_MARKER"; then
        echo -e "${YELLOW}[*] Android 15 resources detected - extracting...${NC}"
        mkdir -p "$WORK_DIR/unknown"
        unzip -q "$SELECTED_APK" "res/*" -d "$WORK_DIR/unknown"
        echo -e "${GREEN}✓ Extracted Android 15 resources${NC}"
    fi

    DECOMPILED_APK="$APK_BASENAME"
    echo -e "${GREEN}✓ Decompiled to ${YELLOW}$WORK_DIR${NC}"
    return 0
}

select_patch_set() {
    [[ -z "$DECOMPILED_APK" ]] && { echo -e "${RED}Decompile an APK first!${NC}"; return 1; }

    local patch_sets=()
    echo -e "${BLUE}[?] Available patch sets:${NC}"
    
    # Find patch directories
    while IFS= read -r -d $'\0' dir; do
        patch_sets+=("$dir")
    done < <(find "$PATCHES_DIR" -maxdepth 1 -type d ! -path "$PATCHES_DIR" -print0)

    if [[ ${#patch_sets[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No patch sets found in $PATCHES_DIR${NC}"
        return 1
    fi

    for i in "${!patch_sets[@]}"; do
        echo -e "  ${GREEN}$((i+1))) ${YELLOW}$(basename "${patch_sets[$i]}")${NC}"
    done

    # Get user selection
    while true; do
        read -rp "$(echo -e "${BLUE}Select patch set (1-${#patch_sets[@]}): ${NC}")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#patch_sets[@]})); then
            SELECTED_PATCH_SET="$(basename "${patch_sets[$((choice-1))]}")"
            return 0
        fi
        echo -e "${RED}Invalid selection! Choose between 1-${#patch_sets[@]}${NC}"
    done
}

apply_patches() {
    [[ -z "$DECOMPILED_APK" ]] && { echo -e "${RED}No decompiled APK!${NC}"; return 1; }
    [[ -z "$SELECTED_PATCH_SET" ]] && { echo -e "${RED}No patch set selected!${NC}"; return 1; }
    
    local patch_target="$PATCHES_DIR/$SELECTED_PATCH_SET"
    local patch_count=$(find "$patch_target" -maxdepth 1 -name '*.patch' | wc -l)
    
    if [[ $patch_count -eq 0 ]]; then
        echo -e "${YELLOW}⚠ No patch files found in $patch_target${NC}"
        return 1
    fi

    echo -e "${GREEN}[+] Applying $patch_count patches from ${YELLOW}$SELECTED_PATCH_SET${GREEN}...${NC}"
    local skipped=0
    local applied=0
    
    for patch in "$patch_target"/*.patch; do
        local patch_name="$(basename "$patch")"
        
        # Dry-run first
        if ! patch --dry-run -d "$WORK_DIR" -p1 -s < "$patch" >/dev/null; then
            echo -e "${RED}  ✗ [DRY-RUN FAILED] ${patch_name}${NC}"
            ((skipped++))
            continue
        fi

        # Actual application
        if patch -d "$WORK_DIR" -p1 -s < "$patch"; then
            echo -e "${GREEN}  ✓ Applied ${patch_name}${NC}"
            ((applied++))
        else
            echo -e "${RED}  ✗ [APPLY FAILED] ${patch_name}${NC}"
            ((skipped++))
        fi
    done

    echo -e "${GREEN}✓ Applied ${applied} patches, skipped ${skipped}${NC}"
    [[ $skipped -eq 0 ]] && return 0 || return 1
}

rebuild_apk() {
    [[ -z "$DECOMPILED_APK" ]] && { echo -e "${RED}Nothing to rebuild!${NC}"; return 1; }
    
    echo -e "${GREEN}[+] Rebuilding ${YELLOW}$DECOMPILED_APK${GREEN} with API ${CURRENT_SDK} (${SDK_VERSIONS[$CURRENT_SDK]})...${NC}"
    
    local rebuilt_apk="$OUTPUT_DIR/rebuilt_$DECOMPILED_APK"
    java -jar "$APKTOOL_JAR" b \
        -c \
        --use-aapt2 \
        "$WORK_DIR" \
        -o "$rebuilt_apk" 2>&1 | tee "$WORK_DIR/rebuild.log"
    
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo -e "${RED}ERROR: Rebuild failed!${NC}"
        echo -e "${YELLOW}Check log: $WORK_DIR/rebuild.log${NC}"
        return 1
    fi
    
    # Add Android 15 resources back if needed
    if [[ -d "$WORK_DIR/unknown" ]]; then
        echo -e "${YELLOW}[*] Reintegrating Android 15 resources...${NC}"
        (cd "$WORK_DIR/unknown" && zip -qr "$rebuilt_apk" .)
        echo -e "${GREEN}✓ Resources integrated${NC}"
    fi

    echo -e "${GREEN}✓ Rebuilt APK: ${YELLOW}$rebuilt_apk${NC}"
    return 0
}

change_sdk_version() {
    echo -e "${BLUE}[?] Available SDK versions:${NC}"
    for sdk in "${!SDK_VERSIONS[@]}"; do
        echo -e "  ${GREEN}$sdk) ${YELLOW}${SDK_VERSIONS[$sdk]}${NC}"
    done
    
    while true; do
        read -rp "$(echo -e "${BLUE}Enter SDK version (${!SDK_VERSIONS[*]}): ${NC}")" choice
        if [[ -n "${SDK_VERSIONS[$choice]}" ]]; then
            CURRENT_SDK="$choice"
            echo -e "${GREEN}✓ SDK version changed to ${CURRENT_SDK} (${SDK_VERSIONS[$CURRENT_SDK]})${NC}"
            return 0
        fi
        echo -e "${RED}Invalid SDK version! Choose from: ${!SDK_VERSIONS[*]}${NC}"
    done
}

function select_framework_res() {
    if [[ -z "$SELECTED_APK" ]]; then
        echo -e "${YELLOW}[!] 📦 Select an APK/JAR to decompile:${NC}"
        select_apk || return 1
    fi

    RES_DIR="$SCRIPT_DIR/framework_res"
    RES_APKS=("$RES_DIR"/*.apk)

    if [[ ${#RES_APKS[@]} -eq 0 ]]; then
        echo -e "${RED}No framework-res.apk found in $RES_DIR!${NC}"
        return 1
    elif [[ ${#RES_APKS[@]} -eq 1 ]]; then
        FRAMEWORK_APK="${RES_APKS[0]}"
    else
        echo -e "${CYAN}📦 Available framework APKs:"
        for i in "${!RES_APKS[@]}"; do
            echo "$((i + 1)). $(basename "${RES_APKS[$i]}")"
        done
        read -rp $'\n➤ Select a framework-res.apk by number: ' CHOICE
        FRAMEWORK_APK="${RES_APKS[$((CHOICE - 1))]}"
    fi

    echo -e "${GREEN}[+] Decompiling ${YELLOW}$(basename "$SELECTED_APK")${GREEN} using framework ${YELLOW}$(basename "$FRAMEWORK_APK")...${NC}"

    rm -rf "$WORK_DIR" 2>/dev/null
    java -jar "$APKTOOL_JAR" d \
        -api "$CURRENT_SDK" \
        -p "$RES_DIR" \
        -b \
        -o "$WORK_DIR" \
        "$SELECTED_APK" 2>&1 | tee "$WORK_DIR/decompile.log"

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo -e "${RED}ERROR: Decompilation failed!${NC}"
        echo -e "${YELLOW}Check log: $WORK_DIR/decompile.log${NC}"
        return 1
    fi

    if unzip -l "$SELECTED_APK" | grep -q "$ANDROID15_MARKER"; then
        echo -e "${YELLOW}[*] Android 15 resources detected - extracting...${NC}"
        mkdir -p "$WORK_DIR/unknown"
        unzip -q "$SELECTED_APK" "res/*" -d "$WORK_DIR/unknown"
        echo -e "${GREEN}✓ Extracted Android 15 resources${NC}"
    fi

    echo -e "${GREEN}✓ Decompiled to ${YELLOW}$WORK_DIR${NC}"
    return 0
}

decompile_nocode() {
    [[ -z "$SELECTED_APK" ]] && { 
        echo -e "${RED}[!] No APK selected. Opening APK selector...${NC}"
        select_apk || return 1
    }

    echo -e "${GREEN}[+] Decompiling ${YELLOW}$APK_BASENAME${GREEN} without smali or resources (manifest only)...${NC}"

    rm -rf "$WORK_DIR" 2>/dev/null
    java -jar "$APKTOOL_JAR" d \
        -api "$CURRENT_SDK" \
        -s \
        -o "$WORK_DIR" \
        "$SELECTED_APK" 2>&1 | tee "$WORK_DIR/decompile.log"

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo -e "${RED}ERROR: Decompilation failed!${NC}"
        echo -e "${YELLOW}Check log: $WORK_DIR/decompile.log${NC}"
        return 1
    fi

    # Handle Android 15 resources if needed
    if unzip -l "$SELECTED_APK" | grep -q "$ANDROID15_MARKER"; then
        echo -e "${YELLOW}[*] Android 15 resources detected - extracting...${NC}"
        mkdir -p "$WORK_DIR/unknown"
        unzip -q "$SELECTED_APK" "res/*" -d "$WORK_DIR/unknown"
        echo -e "${GREEN}✓ Extracted Android 15 resources${NC}"
    fi

    DECOMPILED_APK="$APK_BASENAME"
    echo -e "${GREEN}✓ Decompiled manifest-only to ${YELLOW}$WORK_DIR${NC}"
    return 0
}

decompile_nores() {
    [[ -z "$SELECTED_APK" ]] && { 
        echo -e "${RED}[!] No APK selected. Opening APK selector...${NC}"
        select_apk || return 1
    }

    echo -e "${GREEN}[+] Decompiling ${YELLOW}$APK_BASENAME${GREEN} without smali or resources (manifest only)...${NC}"

    rm -rf "$WORK_DIR" 2>/dev/null
    java -jar "$APKTOOL_JAR" d \
        -api "$CURRENT_SDK" \
        -r \
        -o "$WORK_DIR" \
        "$SELECTED_APK" 2>&1 | tee "$WORK_DIR/decompile.log"

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo -e "${RED}ERROR: Decompilation failed!${NC}"
        echo -e "${YELLOW}Check log: $WORK_DIR/decompile.log${NC}"
        return 1
    fi

    # Handle Android 15 resources if needed
    if unzip -l "$SELECTED_APK" | grep -q "$ANDROID15_MARKER"; then
        echo -e "${YELLOW}[*] Android 15 resources detected - extracting...${NC}"
        mkdir -p "$WORK_DIR/unknown"
        unzip -q "$SELECTED_APK" "res/*" -d "$WORK_DIR/unknown"
        echo -e "${GREEN}✓ Extracted Android 15 resources${NC}"
    fi

    DECOMPILED_APK="$APK_BASENAME"
    echo -e "${GREEN}✓ Decompiled manifest-only to ${YELLOW}$WORK_DIR${NC}"
    return 0
}


cleanup() {
    echo -e "${YELLOW}[*] Cleaning working directory...${NC}"
    [[ -n "$WORK_DIR" ]] && rm -rf "$WORK_DIR"
    DECOMPILED_APK=""
    SELECTED_PATCH_SET=""
    echo -e "${GREEN}✓ Workspace cleaned${NC}"
}

# Main menu loop
while true; do
    show_header
    show_menu
    
    read -rp "$(echo -e "${BLUE}Enter your choice [1-7]: ${NC}")" choice
    case $choice in
        1)
            if verify_environment && select_apk && decompile_apk; then
                read -rp "$(echo -e "${GREEN}Press enter to continue...${NC}")"
            else
                read -rp "$(echo -e "${RED}Operation failed. Press enter to continue...${NC}")"
            fi
            ;;
        2)
            if select_patch_set; then
                read -rp "$(echo -e "${GREEN}Patch set selected. Press enter to continue...${NC}")"
            else
                read -rp "$(echo -e "${RED}No patch sets available. Press enter to continue...${NC}")"
            fi
            ;;
        3)
            if apply_patches; then
                read -rp "$(echo -e "${GREEN}Patching completed. Press enter to continue...${NC}")"
            else
                read -rp "$(echo -e "${YELLOW}Patching completed with errors. Press enter to continue...${NC}")"
            fi
            ;;
        4)
            if rebuild_apk; then
                read -rp "$(echo -e "${GREEN}Rebuild successful. Press enter to continue...${NC}")"
            else
                read -rp "$(echo -e "${RED}Rebuild failed. Press enter to continue...${NC}")"
            fi
            ;;
        5)
            cleanup
            read -rp "$(echo -e "${GREEN}Workspace cleaned. Press enter to continue...${NC}")"
            ;;
        6)
            change_sdk_version
            read -rp "$(echo -e "${GREEN}SDK version changed. Press enter to continue...${NC}")"
            ;;
	    7)
            select_framework_res
            read -rp "$(echo -e \"${GREEN}Framework-res.apk installed. Press enter to continue...${NC}\")"
            ;;
		8)
             echo -e "${BLUE}[*] Decompile without resources selected${NC}"
            decompile_nores
             read -rp "Press enter to continue..."
    ;;
		9)
             echo -e "${BLUE}[*] Decompile without smali selected${NC}"
            decompile_nocode
             read -rp "Press enter to continue..."
    ;;

        10)
            echo -e "${MAGENTA}Exiting...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid option!${NC}"
            sleep 1
            ;;
    esac
done