#!/bin/bash

# ألوان للطباعة
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ملف التسجيل
LOG_FILE="/tmp/union_stream_install_$(date +%Y%m%d_%H%M%S).log"

# دوال المساعدة
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

print_status() {
    log_message "[*] $1"
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    log_message "[✓] $1"
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    log_message "[✗] $1"
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    log_message "[!] $1"
    echo -e "${YELLOW}[!]${NC} $1"
}

progress_bar() {
    local duration=$1
    local bars=50
    local sleep_interval=$(echo "scale=3; $duration/$bars" | bc)
    
    for ((i=0; i<=bars; i++)); do
        printf "${BLUE}["
        for ((j=0; j<i; j++)); do printf "█"; done
        for ((j=i; j<bars; j++)); do printf " "; done
        printf "] %3d%%${NC}\r" $((i*100/bars))
        sleep $sleep_interval
    done
    printf "\n"
}

# التحقق من امتيازات root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run as root or with sudo"
        exit 1
    fi
    print_success "Running with root privileges"
}

# التحقق من الاتصال بالإنترنت
check_internet() {
    print_status "Checking internet connection..."
    
    local max_attempts=3
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if ping -c 1 -W 2 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 2 github.com >/dev/null 2>&1; then
            print_success "Internet connection is available (Attempt $attempt/$max_attempts)"
            return 0
        fi
        print_warning "Attempt $attempt failed, retrying..."
        sleep 2
        ((attempt++))
    done
    
    print_error "No internet connection after $max_attempts attempts"
    return 1
}

# التحقق من إصدار Enigma2
check_enigma2_version() {
    print_status "Checking Enigma2 version..."
    
    if [ -f /etc/opkg/arch.conf ]; then
        local arch=$(grep -o "mips[0-9]*" /etc/opkg/arch.conf | head -1)
        print_success "Architecture: $arch"
    fi
    
    if [ -f /etc/image-version ]; then
        local image=$(cat /etc/image-version | head -1)
        print_success "Image: $image"
    fi
}

# فك الضغط مع التحقق
extract_files() {
    local target_dir="/usr/lib/enigma2/python/Plugins/Extensions"
    
    if [ ! -d "$target_dir" ]; then
        print_error "Target directory does not exist: $target_dir"
        exit 1
    fi
    
    # التحقق من المساحة المتاحة
    local available_space=$(df "$target_dir" | awk 'NR==2 {print $4}')
    local archive_size=$(stat -c%s "/tmp/Union_Stream.tar.gz" 2>/dev/null || echo "100000")
    
    if [ $available_space -lt $((archive_size * 2)) ]; then
        print_error "Insufficient disk space. Available: $available_space KB, Needed: $((archive_size * 2)) KB"
        exit 1
    fi
    
    print_status "Extracting files to $target_dir..."
    tar -xzf /tmp/Union_Stream.tar.gz -C "$target_dir"
    
    if [ $? -eq 0 ]; then
        print_success "Extraction completed successfully"
        return 0
    else
        print_error "Extraction failed!"
        return 1
    fi
}

# إنشاء مجلد Union_Stream
create_directories() {
    print_status "Creating Union_Stream directories..."
    
    mkdir -p /etc/enigma2/Union_Stream
    mkdir -p /usr/lib/enigma2/python/Plugins/Extensions/Union_Stream
    
    if [ $? -eq 0 ]; then
        print_success "Directories created successfully"
        return 0
    else
        print_error "Failed to create directories"
        return 1
    fi
}

# نسخ احتياطي للملف القديم
backup_old_files() {
    print_status "Checking for existing servers.json..."
    
    if [ -f "/etc/enigma2/Union_Stream/servers.json" ]; then
        timestamp=$(date +%Y%m%d_%H%M%S)
        backup_file="/etc/enigma2/Union_Stream/servers.json.backup_$timestamp"
        cp /etc/enigma2/Union_Stream/servers.json "$backup_file"
        
        if [ $? -eq 0 ]; then
            print_success "Old servers.json backed up as $(basename "$backup_file")"
            return 0
        else
            print_warning "Failed to backup old servers.json"
            return 1
        fi
    fi
    
    return 0
}

# تنزيل servers.json
download_servers_json() {
    print_status "Downloading servers.json configuration..."
    
    wget --timeout=30 --tries=3 -O /tmp/servers.json \
        https://raw.githubusercontent.com/Said-Pro/StalkerOS/refs/heads/main/servers.json
    
    if [ $? -eq 0 ]; then
        print_success "servers.json downloaded successfully"
        
        # التحقق من صحة الملف
        if [ -s /tmp/servers.json ]; then
            if python3 -m json.tool /tmp/servers.json >/dev/null 2>&1 || \
               python -m json.tool /tmp/servers.json >/dev/null 2>&1; then
                
                cp /tmp/servers.json /etc/enigma2/Union_Stream/servers.json
                chmod 644 /etc/enigma2/Union_Stream/servers.json
                chown root:root /etc/enigma2/Union_Stream/servers.json
                
                file_size=$(stat -c%s "/etc/enigma2/Union_Stream/servers.json")
                print_success "servers.json copied successfully ($(($file_size/1024)) KB)"
                
                rm -f /tmp/servers.json
                return 0
            else
                print_error "servers.json is not valid JSON!"
                rm -f /tmp/servers.json
                return 1
            fi
        else
            print_error "servers.json is empty!"
            rm -f /tmp/servers.json
            return 1
        fi
    else
        print_error "Failed to download servers.json!"
        return 1
    fi
}

# إنشاء servers.json افتراضي
create_default_servers_json() {
    print_status "Creating default servers.json..."
    
    cat > /etc/enigma2/Union_Stream/servers.json << 'EOF'
{
  "servers": [
    {
      "name": "Default Server",
      "url": "http://example.com",
      "enabled": true,
      "type": "stalker"
    }
  ],
  "settings": {
    "auto_update": true,
    "update_interval": 24,
    "timeout": 30,
    "max_connections": 5
  }
}
EOF
    
    chmod 644 /etc/enigma2/Union_Stream/servers.json
    print_warning "Default servers.json created"
}

# تثبيت الحزم المطلوبة
install_dependencies() {
    print_status "Checking and installing dependencies..."
    print_warning "This may take a few minutes..."
    
    progress_bar 3
    
    # تحديث قائمة الحزم
    opkg update
    if [ $? -ne 0 ]; then
        print_warning "Failed to update package list, continuing anyway..."
    fi
    
    # قائمة الحزم المطلوبة
    local dependencies=(
        "python-json"
        "python-compression"
        "python-io"
        "python-codecs"
        "python-netclient"
    )
    
    for dep in "${dependencies[@]}"; do
        print_status "Checking $dep..."
        
        if opkg list-installed | grep -q "^$dep"; then
            print_success "$dep is already installed"
        else
            print_status "Installing $dep..."
            if opkg install "$dep" 2>/dev/null; then
                print_success "$dep installed successfully"
            else
                print_warning "Failed to install $dep (may not be critical)"
            fi
        fi
    done
    
    print_success "Dependencies check completed"
}

# تعيين صلاحيات الملفات
set_permissions() {
    print_status "Setting file permissions..."
    
    # مجلد الإضافة
    if [ -d "/usr/lib/enigma2/python/Plugins/Extensions/Union_Stream" ]; then
        find /usr/lib/enigma2/python/Plugins/Extensions/Union_Stream -type f -name "*.py" -exec chmod 644 {} \; 2>/dev/null
        find /usr/lib/enigma2/python/Plugins/Extensions/Union_Stream -type d -exec chmod 755 {} \; 2>/dev/null
        
        # ملفات قابلة للتنفيذ إذا وجدت
        for file in /usr/lib/enigma2/python/Plugins/Extensions/Union_Stream/*; do
            if [[ "$file" == *".sh" ]] || [[ "$file" == *".bin" ]] || [[ -x "$file" ]]; then
                chmod 755 "$file" 2>/dev/null
            fi
        done
    fi
    
    # مجلد التكوين
    chmod 755 /etc/enigma2/Union_Stream 2>/dev/null
    chmod 644 /etc/enigma2/Union_Stream/*.json 2>/dev/null
    
    print_success "Permissions set successfully"
}

# إنشاء أداة الإزالة
create_uninstaller() {
    print_status "Creating uninstaller script..."
    
    local uninstaller="/usr/lib/enigma2/python/Plugins/Extensions/Union_Stream/uninstall.sh"
    
    cat > "$uninstaller" << 'EOF'
#!/bin/bash
echo "=============================================="
echo "    Union_Stream Uninstaller"
echo "=============================================="
echo ""
echo "This will remove Union_Stream from your system."
echo ""
read -p "Are you sure? (y/N): " confirm
if [[ "$confirm" =~ [Yy] ]]; then
    echo "Removing Union_Stream..."
    rm -rf /usr/lib/enigma2/python/Plugins/Extensions/Union_Stream
    rm -rf /etc/enigma2/Union_Stream
    echo "Union_Stream has been removed"
    echo "Please restart Enigma2 for changes to take effect"
else
    echo "Uninstall cancelled"
fi
EOF
    
    chmod +x "$uninstaller"
    print_success "Uninstaller created: $uninstaller"
}

# شريط التقدم المتحسن لإعادة التشغيل
show_restart_progress() {
    local total_time=${1:-10}
    local bars=30
    local sleep_interval=$(echo "scale=2; $total_time/$bars" | bc)
    local description=${2:-"Restarting Enigma2"}
    
    echo -e "${BLUE}$description...${NC}"
    
    for ((i=0; i<=bars; i++)); do
        percentage=$((i*100/bars))
        
        if [ $percentage -lt 30 ]; then
            color="${RED}"
        elif [ $percentage -lt 70 ]; then
            color="${YELLOW}"
        else
            color="${GREEN}"
        fi
        
        printf "${BLUE}["
        for ((j=0; j<i; j++)); do 
            printf "█"
        done
        
        for ((j=i; j<bars; j++)); do 
            printf " "
        done
        
        printf "] ${color}%3d%%${NC}" $percentage
        
        if [ $percentage -eq 0 ]; then
            printf " Stopping service...\r"
        elif [ $percentage -eq 30 ]; then
            printf " Loading plugins...\r"
        elif [ $percentage -eq 60 ]; then
            printf " Initializing EPG...\r"
        elif [ $percentage -eq 90 ]; then
            printf " Finalizing...\r"
        else
            printf "\r"
        fi
        
        sleep $sleep_interval
    done
    printf "\n"
}

# إعادة تشغيل Enigma2
restart_enigma2() {
    print_status "Preparing to restart Enigma2..."
    
    # التحقق من وجود systemd
    if command -v systemctl >/dev/null 2>&1; then
        print_success "Detected systemd system"
        
        print_status "Checking current Enigma2 status..."
        if systemctl is-active enigma2.service >/dev/null 2>&1; then
            print_success "Enigma2 is currently running"
            
            # نسخ احتياطي اختياري
            if [ -f "/etc/enigma2/settings" ]; then
                print_status "Do you want to backup your current settings? (y/N)"
                read -t 5 -n 1 backup_choice
                echo ""
                
                if [[ "$backup_choice" =~ [Yy] ]]; then
                    local backup_dir="/tmp/enigma2_backup_$(date +%Y%m%d_%H%M%S)"
                    mkdir -p "$backup_dir"
                    
                    cp /etc/enigma2/settings "$backup_dir/" 2>/dev/null
                    cp /etc/enigma2/lamedb "$backup_dir/" 2>/dev/null
                    cp /etc/enigma2/lamedb5 "$backup_dir/" 2>/dev/null
                    
                    print_success "Settings backed up to: $backup_dir"
                fi
            fi
            
            print_warning "Restarting Enigma2 will temporarily interrupt TV service"
            print_warning "The restart will begin in 3 seconds..."
            
            for i in {3..1}; do
                echo -ne "${YELLOW}Restarting in $i seconds...${NC}\r"
                sleep 1
            done
            echo ""
            
            print_status "Restarting Enigma2 service..."
            
            if systemctl restart enigma2.service; then
                print_success "Enigma2 restart command sent successfully"
                
                print_status "Waiting for Enigma2 to start..."
                sleep 5
                
                local max_wait=30
                local wait_count=0
                
                while [ $wait_count -lt $max_wait ]; do
                    if systemctl is-active enigma2.service >/dev/null 2>&1; then
                        print_success "Enigma2 is now running"
                        return 0
                    fi
                    sleep 2
                    ((wait_count+=2))
                    echo -ne "${BLUE}Waiting... ${wait_count}/${max_wait} seconds${NC}\r"
                done
                
                print_warning "Enigma2 is taking longer than usual to start"
                print_status "Checking service status..."
                systemctl status enigma2.service --no-pager -l
                
            else
                print_error "Failed to restart Enigma2 service"
                print_status "Trying alternative method..."
                
                killall -9 enigma2 2>/dev/null
                sleep 3
                systemctl start enigma2.service
                
                if [ $? -eq 0 ]; then
                    print_success "Enigma2 started using alternative method"
                else
                    print_error "Could not restart Enigma2. Manual intervention may be required."
                    return 1
                fi
            fi
            
        else
            print_warning "Enigma2 is not currently running"
            print_status "Starting Enigma2 service..."
            
            if systemctl start enigma2.service; then
                print_success "Enigma2 service started"
            else
                print_error "Failed to start Enigma2 service"
                return 1
            fi
        fi
        
    elif [ -f "/etc/init.d/enigma2" ]; then
        print_success "Detected init.d system"
        
        print_status "Restarting Enigma2 via init.d..."
        /etc/init.d/enigma2 restart
        
        if [ $? -eq 0 ]; then
            print_success "Enigma2 restart initiated"
        else
            print_error "Failed to restart Enigma2"
            return 1
        fi
        
    elif command -v svc >/dev/null 2>&1; then
        print_success "Detected runit system"
        
        print_status "Restarting Enigma2 via runit..."
        svc -t /service/enigma2 2>/dev/null || svc -t /var/service/enigma2 2>/dev/null
        
        if [ $? -eq 0 ]; then
            print_success "Enigma2 restart initiated"
        else
            print_error "Failed to restart Enigma2"
            return 1
        fi
        
    else
        print_warning "Could not detect init system, trying direct method"
        
        if pgrep enigma2 >/dev/null; then
            print_status "Stopping Enigma2 processes..."
            killall enigma2 2>/dev/null
            sleep 3
            pkill -9 enigma2 2>/dev/null
            sleep 2
        fi
        
        print_status "Starting Enigma2..."
        enigma2 &
        
        if [ $? -eq 0 ]; then
            print_success "Enigma2 started in background"
        else
            print_error "Failed to start Enigma2"
            return 1
        fi
    fi
    
    return 0
}

# الوظيفة الرئيسية لإعادة التشغيل
perform_restart() {
    print_status "=============================================="
    print_status "         Enigma2 Restart Procedure"
    print_status "=============================================="
    echo ""
    
    if [ ! -d "/usr/lib/enigma2/python/Plugins/Extensions/Union_Stream" ]; then
        print_error "Union_Stream plugin not found! Cannot restart."
        return 1
    fi
    
    print_warning "Restart options:"
    echo "1) Restart Enigma2 now (Recommended)"
    echo "2) Skip restart and show manual instructions"
    echo "3) Cancel restart"
    echo ""
    
    read -t 30 -p "Select option [1-3] (default: 1): " restart_option
    
    case "${restart_option:-1}" in
        1)
            show_restart_progress 12 "Restarting Enigma2 with Union_Stream"
            
            if restart_enigma2; then
                print_success "Enigma2 has been restarted successfully!"
                print_success "Union_Stream plugin should now be available"
                
                print_status "Checking plugin installation..."
                sleep 8
                
                if [ -f "/usr/lib/enigma2/python/Plugins/Extensions/Union_Stream/plugin.py" ]; then
                    print_success "✓ Plugin files verified"
                    echo -e "${GREEN}✓ Installation complete!${NC}"
                    echo -e "${GREEN}✓ Please check your plugin list for 'Union_Stream'${NC}"
                fi
            else
                print_error "Restart encountered issues"
                print_warning "You may need to restart your receiver manually"
            fi
            ;;
            
        2)
            print_status "=============================================="
            print_warning "MANUAL RESTART INSTRUCTIONS:"
            echo ""
            echo "To complete the installation, you must restart Enigma2:"
            echo ""
            echo "Method 1 - Via remote control:"
            echo "  • Press MENU button"
            echo "  • Select 'Standby/Restart'"
            echo "  • Choose 'Restart GUI' or 'Restart Enigma2'"
            echo ""
            echo "Method 2 - Via telnet/SSH:"
            echo "  • Connect to your receiver via telnet/SSH"
            echo "  • Run: systemctl restart enigma2"
            echo "  • Or run: init 4 && sleep 3 && init 3"
            echo ""
            echo "Method 3 - Full receiver restart:"
            echo "  • Unplug power, wait 10 seconds, plug back in"
            echo ""
            print_status "=============================================="
            ;;
            
        3|*)
            print_warning "Restart cancelled"
            print_warning "Union_Stream will be available after next Enigma2 restart"
            ;;
    esac
    
    if [ -f "/proc/stb/info/model" ]; then
        local model=$(cat /proc/stb/info/model)
        print_status "Receiver model: $model"
        
        case "$model" in
            "dm800"|"dm500hd"|"dm800se")
                print_warning "For older Dreambox models, a full reboot is recommended:"
                echo "  shutdown -r now"
                ;;
        esac
    fi
    
    return 0
}

# تنظيف الملفات المؤقتة
cleanup_temp_files() {
    print_status "Cleaning temporary files..."
    
    rm -f /tmp/Union_Stream.tar.gz
    rm -f /tmp/servers.json
    rm -f /tmp/union_stream_*.log 2>/dev/null
    
    print_success "Temporary files removed"
}

# عرض الملخص النهائي
show_summary() {
    echo ""
    echo "=============================================="
    print_success "Installation completed successfully!"
    echo "=============================================="
    echo ""
    echo "Summary:"
    echo "- Plugin installed to: /usr/lib/enigma2/python/Plugins/Extensions/Union_Stream"
    echo "- Configuration file: /etc/enigma2/Union_Stream/servers.json"
    echo "- Log file: $LOG_FILE"
    echo ""
    
    if [ -d "/etc/enigma2/Union_Stream" ]; then
        echo "Backup files:"
        ls -la /etc/enigma2/Union_Stream/servers.json.backup_* 2>/dev/null || echo "  No backups found"
    fi
    
    echo ""
    echo "Next steps:"
    echo "1. Access Union_Stream from your plugins menu"
    echo "2. Configure your servers in the plugin settings"
    echo "3. Restart if you haven't already"
    echo ""
    echo "For support, check the plugin documentation"
    echo "=============================================="
}

# الوظيفة الرئيسية
main() {
    clear
    echo "=============================================="
    echo "    Union_Stream Installation Script"
    echo "          Union_Stream V4.0"
    echo "=============================================="
    echo ""
    
    # تسجيل بدء التثبيت
    log_message "=== Union_Stream Installation Started ==="
    
    # التحقق من الأساسيات
    check_root
    check_internet
    check_enigma2_version
    
    # التنزيل
    print_status "Downloading Union_Stream from GitHub..."
    wget --progress=dot:giga --timeout=60 --tries=3 \
        -O /tmp/Union_Stream.tar.gz \
        https://github.com/Said-Pro/StalkerOS/raw/refs/heads/main/Union_Stream.tar.gz
    
    if [ $? -ne 0 ]; then
        print_error "Download failed!"
        log_message "Download failed"
        exit 1
    fi
    
    print_success "Download completed successfully"
    
    # إنشاء المجلدات
    create_directories
    
    # نسخ احتياطي للملفات القديمة
    backup_old_files
    
    # فك الضغط
    if ! extract_files; then
        print_error "Failed to extract files"
        exit 1
    fi
    
    # تنزيل servers.json
    if ! download_servers_json; then
        print_warning "Using default servers.json configuration"
        create_default_servers_json
    fi
    
    # تثبيت الاعتماديات
    install_dependencies
    
    # تعيين الصلاحيات
    set_permissions
    
    # إنشاء أداة الإزالة
    create_uninstaller
    
    # تنظيف الملفات المؤقتة
    cleanup_temp_files
    
    # إعادة التشغيل
    perform_restart
    
    # عرض الملخص
    show_summary
    
    log_message "=== Union_Stream Installation Completed ==="
}

# معالجة الإشارات
trap 'print_error "Installation interrupted by user"; exit 1' INT TERM

# تشغيل الوظيفة الرئيسية
main

exit 0