#!/bin/bash

# ألوان للطباعة
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# دوال المساعدة
print_status() {
    echo -e "${BLUE}[*]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
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

clear
echo "=============================================="
echo "    Union_Stream Installation Script"
echo "          Union_Stream V4.0"
echo "=============================================="
echo ""

# التحقق من الاتصال بالإنترنت
print_status "Checking internet connection..."
if ping -c 1 github.com >/dev/null 2>&1; then
    print_success "Internet connection is available"
else
    print_error "No internet connection!"
    exit 1
fi

# التنزيل
print_status "Downloading Union_Stream from GitHub..."
wget -O /tmp/Union_Stream.tar.gz https://github.com/Said-Pro/StalkerOS/raw/refs/heads/main/Union_Stream.tar.gz

if [ $? -eq 0 ]; then
    print_success "Download completed successfully"
else
    print_error "Download failed!"
    exit 1
fi

# فك الضغط
print_status "Extracting files to plugins directory..."
cd /tmp/
tar -xzf Union_Stream.tar.gz -C /usr/lib/enigma2/python/Plugins/Extensions

if [ $? -eq 0 ]; then
    print_success "Extraction completed successfully"
else
    print_error "Extraction failed!"
    exit 1
fi

# إنشاء مجلد Union_Stream
print_status "Creating Union_Stream directory..."
mkdir -p /etc/enigma2/Union_Stream

if [ $? -eq 0 ]; then
    print_success "Directory created successfully"
else
    print_error "Failed to create directory!"
    exit 1
fi

# نسخ احتياطي للملف القديم إذا كان موجوداً
print_status "Checking for existing servers.json..."
if [ -f "/etc/enigma2/Union_Stream/servers.json" ]; then
    timestamp=$(date +%Y%m%d_%H%M%S)
    cp /etc/enigma2/Union_Stream/servers.json "/etc/enigma2/Union_Stream/servers.json.backup_$timestamp"
    print_success "Old servers.json backed up as servers.json.backup_$timestamp"
fi

# تحميل ملف servers.json
print_status "Downloading servers.json configuration..."
wget -O /tmp/servers.json https://raw.githubusercontent.com/Said-Pro/StalkerOS/refs/heads/main/servers.json

if [ $? -eq 0 ]; then
    print_success "servers.json downloaded successfully"
    
    # التحقق من صحة الملف
    if [ -s /tmp/servers.json ]; then
        # التحقق من أن الملف يحتوي على JSON صالح
        if python3 -m json.tool /tmp/servers.json >/dev/null 2>&1; then
            # نسخ الملف إلى المسار النهائي
            cp /tmp/servers.json /etc/enigma2/Union_Stream/servers.json
            
            # تعيين الصلاحيات المناسبة
            chmod 644 /etc/enigma2/Union_Stream/servers.json
            chown root:root /etc/enigma2/Union_Stream/servers.json
            
            print_success "servers.json copied to /etc/enigma2/Union_Stream/"
            print_success "File permissions set correctly"
            
            # عرض حجم الملف
            file_size=$(stat -c%s "/etc/enigma2/Union_Stream/servers.json")
            echo -e "${GREEN}[✓]${NC} File size: $(($file_size/1024)) KB"
            
            # تنظيف الملف المؤقت
            rm -f /tmp/servers.json
            
        else
            print_error "servers.json is not valid JSON!"
            
            # إذا كان هناك نسخة احتياطية، استرجعها
            if ls /etc/enigma2/Union_Stream/servers.json.backup_* 2>/dev/null | head -1; then
                latest_backup=$(ls -t /etc/enigma2/Union_Stream/servers.json.backup_* | head -1)
                cp "$latest_backup" /etc/enigma2/Union_Stream/servers.json
                print_warning "Restored servers.json from backup"
            fi
            
            rm -f /tmp/servers.json
            exit 1
        fi
    else
        print_error "servers.json is empty!"
        rm -f /tmp/servers.json
        exit 1
    fi
else
    print_error "Failed to download servers.json!"
    
    # إذا فشل التحميل، استخدم ملف افتراضي
    print_status "Creating default servers.json..."
    echo '{
  "servers": [
    {
      "name": "Default Server",
      "url": "http://example.com",
      "enabled": true
    }
  ],
  "settings": {
    "auto_update": true,
    "update_interval": 24,
    "timeout": 30
  }
}' > /etc/enigma2/Union_Stream/servers.json
    
    chmod 644 /etc/enigma2/Union_Stream/servers.json
    print_warning "Default servers.json created"
fi

# تنظيف الملف المؤقت الرئيسي
print_status "Cleaning temporary files..."
rm -f /tmp/Union_Stream.tar.gz
print_success "Temporary files removed"

# تثبيت الحزم المطلوبة
print_status "Updating package list and installing dependencies..."
print_warning "This may take a few minutes..."
progress_bar 5

opkg update
if [ $? -eq 0 ]; then
    print_success "Package list updated"
else
    print_error "Failed to update package list"
    exit 1
fi

# التحقق من تثبيت python-json
print_status "Checking for JSON module..."
if opkg list-installed | grep -q python-json; then
    print_success "Python JSON module is installed"
else
    print_status "Installing python-json module..."
    opkg install python-json
    if [ $? -eq 0 ]; then
        print_success "Python JSON module installed"
    else
        print_warning "Failed to install python-json module"
    fi
fi

# إعادة التشغيل
print_status "Restarting Enigma2..."
print_warning "Please wait while the system restarts..."
progress_bar 3

systemctl restart enigma2

echo ""
echo "=============================================="
print_success "Installation completed successfully!"
print_success "Union_Stream has been installed and activated"
print_success "servers.json has been configured"
echo "=============================================="
echo ""
echo "Summary:"
echo "- Plugin installed to: /usr/lib/enigma2/python/Plugins/Extensions"
echo "- Configuration file: /etc/enigma2/Union_Stream/servers.json"
echo "- Backup created: /etc/enigma2/Union_Stream/servers.json.backup_*"
echo ""
