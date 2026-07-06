#!/bin/bash
#
# SBOM 生成脚本
# 支持 Maven 项目和 Go 项目的 SBOM 生成
#
# 使用方法:
#   ./generate-sbom.sh [选项]
#
# 选项:
#   -p, --project <path>     项目路径 (默认: 当前目录)
#   -t, --type <type>        项目类型: maven|go|auto (默认: auto)
#   -f, --format <format>    输出格式: cyclonedx-json|cyclonedx-xml|spdx-json|spdx-tv|all (默认: cyclonedx-json)
#   -o, --output <path>      输出目录 (默认: ./sbom)
#   -v, --version <version>  项目版本 (默认: 从项目读取或1.0.0)
#   -h, --help               显示帮助信息
#
# 示例:
#   ./generate-sbom.sh -p ./demo-a-springboot -t maven -f all
#   ./generate-sbom.sh -p ./demo-b-golang -t go -o ./sbom-output
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
PROJECT_PATH="."
PROJECT_TYPE="auto"
OUTPUT_FORMAT="cyclonedx-json"
OUTPUT_DIR="./sbom"
PROJECT_VERSION=""

# 工具检查
SYFT_CMD=""
MAVEN_CMD=""

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 显示帮助信息
show_help() {
    head -n 20 "$0" | tail -n 18
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -p|--project)
                PROJECT_PATH="$2"
                shift 2
                ;;
            -t|--type)
                PROJECT_TYPE="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -v|--version)
                PROJECT_VERSION="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# 检查依赖工具
check_dependencies() {
    log_info "检查依赖工具..."
    
    # 检查 syft
    if command -v syft &> /dev/null; then
        SYFT_CMD="syft"
        log_success "找到 syft: $(syft version | head -n 1)"
    elif command -v docker &> /dev/null; then
        SYFT_CMD="docker run --rm -v $(pwd):/workspace anchore/syft:latest"
        log_success "将使用 Docker 运行 syft"
    else
        log_error "未找到 syft 或 Docker，请先安装"
        log_info "安装 syft: curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin"
        exit 1
    fi
    
    # 检查 Maven
    if command -v mvn &> /dev/null; then
        MAVEN_CMD="mvn"
        log_success "找到 Maven: $(mvn -version | head -n 1)"
    else
        log_warn "未找到 Maven，Maven 项目将无法使用 Maven 插件生成 SBOM"
    fi
}

# 自动检测项目类型
detect_project_type() {
    if [ "$PROJECT_TYPE" != "auto" ]; then
        return
    fi
    
    log_info "自动检测项目类型..."
    
    cd "$PROJECT_PATH"
    
    if [ -f "pom.xml" ]; then
        PROJECT_TYPE="maven"
        log_success "检测到 Maven 项目"
    elif [ -f "go.mod" ]; then
        PROJECT_TYPE="go"
        log_success "检测到 Go 项目"
    elif [ -f "package.json" ]; then
        PROJECT_TYPE="nodejs"
        log_success "检测到 Node.js 项目"
    else
        log_error "无法自动检测项目类型，请使用 -t 参数指定"
        exit 1
    fi
}

# 获取项目信息
get_project_info() {
    cd "$PROJECT_PATH"
    
    if [ -z "$PROJECT_VERSION" ]; then
        case $PROJECT_TYPE in
            maven)
                if [ -f "pom.xml" ]; then
                    PROJECT_VERSION=$(grep -oP '(?<=<version>)[^<]+' pom.xml | head -n 1)
                fi
                ;;
            go)
                if [ -f "go.mod" ]; then
                    # 尝试从 git tag 获取版本
                    if command -v git &> /dev/null && git describe --tags &> /dev/null; then
                        PROJECT_VERSION=$(git describe --tags --always)
                    fi
                fi
                ;;
        esac
        
        # 默认版本
        if [ -z "$PROJECT_VERSION" ]; then
            PROJECT_VERSION="1.0.0"
        fi
    fi
    
    # 获取项目名称
    if [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME=$(basename "$(cd "$PROJECT_PATH" && pwd)")
    fi
    
    log_info "项目名称: $PROJECT_NAME"
    log_info "项目版本: $PROJECT_VERSION"
}

# 生成 SBOM 文件名
generate_filename() {
    local format=$1
    local timestamp=$(date +%Y%m%d_%H%M%S)
    echo "${PROJECT_NAME}-${PROJECT_VERSION}-${format}-${timestamp}"
}

# 生成 Maven 项目 SBOM
generate_maven_sbom() {
    log_info "生成 Maven 项目 SBOM..."
    
    cd "$PROJECT_PATH"
    
    # 创建输出目录
    mkdir -p "$OUTPUT_DIR"
    
    # 方法1: 使用 CycloneDX Maven 插件
    if [ -n "$MAVEN_CMD" ]; then
        log_info "使用 CycloneDX Maven 插件生成 SBOM..."
        
        # 检查是否有 CycloneDX 插件
        if ! grep -q "cyclonedx-maven-plugin" pom.xml 2>/dev/null; then
            log_warn "pom.xml 中未找到 CycloneDX 插件，将使用 syft 生成"
        else
            $MAVEN_CMD cyclonedx:makeAggregateBom -q
            
            if [ -f "target/bom.json" ]; then
                local filename=$(generate_filename "cyclonedx-json")
                cp "target/bom.json" "$OUTPUT_DIR/${filename}.json"
                log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.json"
            fi
            
            if [ -f "target/bom.xml" ]; then
                local filename=$(generate_filename "cyclonedx-xml")
                cp "target/bom.xml" "$OUTPUT_DIR/${filename}.xml"
                log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.xml"
            fi
            
            return
        fi
    fi
    
    # 方法2: 使用 syft
    log_info "使用 syft 生成 SBOM..."
    
    case $OUTPUT_FORMAT in
        cyclonedx-json)
            local filename=$(generate_filename "cyclonedx-json")
            $SYFT_CMD packages dir:. -o cyclonedx-json > "$OUTPUT_DIR/${filename}.json"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.json"
            ;;
        cyclonedx-xml)
            local filename=$(generate_filename "cyclonedx-xml")
            $SYFT_CMD packages dir:. -o cyclonedx-xml > "$OUTPUT_DIR/${filename}.xml"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.xml"
            ;;
        spdx-json)
            local filename=$(generate_filename "spdx-json")
            $SYFT_CMD packages dir:. -o spdx-json > "$OUTPUT_DIR/${filename}.spdx.json"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.spdx.json"
            ;;
        spdx-tv)
            local filename=$(generate_filename "spdx-tv")
            $SYFT_CMD packages dir:. -o spdx-tv > "$OUTPUT_DIR/${filename}.spdx"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.spdx"
            ;;
        all)
            local filename=$(generate_filename "cyclonedx-json")
            $SYFT_CMD packages dir:. -o cyclonedx-json > "$OUTPUT_DIR/${filename}.json"
            
            filename=$(generate_filename "cyclonedx-xml")
            $SYFT_CMD packages dir:. -o cyclonedx-xml > "$OUTPUT_DIR/${filename}.xml"
            
            filename=$(generate_filename "spdx-json")
            $SYFT_CMD packages dir:. -o spdx-json > "$OUTPUT_DIR/${filename}.spdx.json"
            
            log_success "所有格式 SBOM 已生成到: $OUTPUT_DIR"
            ;;
        *)
            log_error "不支持的格式: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

# 生成 Go 项目 SBOM
generate_go_sbom() {
    log_info "生成 Go 项目 SBOM..."
    
    cd "$PROJECT_PATH"
    
    # 创建输出目录
    mkdir -p "$OUTPUT_DIR"
    
    case $OUTPUT_FORMAT in
        cyclonedx-json)
            local filename=$(generate_filename "cyclonedx-json")
            $SYFT_CMD packages dir:. -o cyclonedx-json > "$OUTPUT_DIR/${filename}.json"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.json"
            ;;
        cyclonedx-xml)
            local filename=$(generate_filename "cyclonedx-xml")
            $SYFT_CMD packages dir:. -o cyclonedx-xml > "$OUTPUT_DIR/${filename}.xml"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.xml"
            ;;
        spdx-json)
            local filename=$(generate_filename "spdx-json")
            $SYFT_CMD packages dir:. -o spdx-json > "$OUTPUT_DIR/${filename}.spdx.json"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.spdx.json"
            ;;
        spdx-tv)
            local filename=$(generate_filename "spdx-tv")
            $SYFT_CMD packages dir:. -o spdx-tv > "$OUTPUT_DIR/${filename}.spdx"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.spdx"
            ;;
        all)
            local filename=$(generate_filename "cyclonedx-json")
            $SYFT_CMD packages dir:. -o cyclonedx-json > "$OUTPUT_DIR/${filename}.json"
            
            filename=$(generate_filename "cyclonedx-xml")
            $SYFT_CMD packages dir:. -o cyclonedx-xml > "$OUTPUT_DIR/${filename}.xml"
            
            filename=$(generate_filename "spdx-json")
            $SYFT_CMD packages dir:. -o spdx-json > "$OUTPUT_DIR/${filename}.spdx.json"
            
            log_success "所有格式 SBOM 已生成到: $OUTPUT_DIR"
            ;;
        *)
            log_error "不支持的格式: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

# 生成 Node.js 项目 SBOM
generate_nodejs_sbom() {
    log_info "生成 Node.js 项目 SBOM..."
    
    cd "$PROJECT_PATH"
    
    # 创建输出目录
    mkdir -p "$OUTPUT_DIR"
    
    case $OUTPUT_FORMAT in
        cyclonedx-json)
            local filename=$(generate_filename "cyclonedx-json")
            $SYFT_CMD packages dir:. -o cyclonedx-json > "$OUTPUT_DIR/${filename}.json"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.json"
            ;;
        cyclonedx-xml)
            local filename=$(generate_filename "cyclonedx-xml")
            $SYFT_CMD packages dir:. -o cyclonedx-xml > "$OUTPUT_DIR/${filename}.xml"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.xml"
            ;;
        spdx-json)
            local filename=$(generate_filename "spdx-json")
            $SYFT_CMD packages dir:. -o spdx-json > "$OUTPUT_DIR/${filename}.spdx.json"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.spdx.json"
            ;;
        spdx-tv)
            local filename=$(generate_filename "spdx-tv")
            $SYFT_CMD packages dir:. -o spdx-tv > "$OUTPUT_DIR/${filename}.spdx"
            log_success "SBOM 已生成: $OUTPUT_DIR/${filename}.spdx"
            ;;
        all)
            local filename=$(generate_filename "cyclonedx-json")
            $SYFT_CMD packages dir:. -o cyclonedx-json > "$OUTPUT_DIR/${filename}.json"
            
            filename=$(generate_filename "cyclonedx-xml")
            $SYFT_CMD packages dir:. -o cyclonedx-xml > "$OUTPUT_DIR/${filename}.xml"
            
            filename=$(generate_filename "spdx-json")
            $SYFT_CMD packages dir:. -o spdx-json > "$OUTPUT_DIR/${filename}.spdx.json"
            
            log_success "所有格式 SBOM 已生成到: $OUTPUT_DIR"
            ;;
        *)
            log_error "不支持的格式: $OUTPUT_FORMAT"
            exit 1
            ;;
    esac
}

# 生成容器镜像 SBOM
generate_image_sbom() {
    local image_name=$1
    
    log_info "生成容器镜像 SBOM: $image_name"
    
    mkdir -p "$OUTPUT_DIR"
    
    local filename=$(generate_filename "image-cyclonedx-json")
    $SYFT_CMD packages "$image_name" -o cyclonedx-json > "$OUTPUT_DIR/${filename}.json"
    log_success "镜像 SBOM 已生成: $OUTPUT_DIR/${filename}.json"
}

# 验证 SBOM
validate_sbom() {
    log_info "验证 SBOM 文件..."
    
    local sbom_file=$1
    
    if [ ! -f "$sbom_file" ]; then
        log_error "SBOM 文件不存在: $sbom_file"
        return 1
    fi
    
    # 检查文件大小
    local file_size=$(stat -f%z "$sbom_file" 2>/dev/null || stat -c%s "$sbom_file" 2>/dev/null)
    if [ "$file_size" -lt 100 ]; then
        log_warn "SBOM 文件可能为空或损坏"
        return 1
    fi
    
    # 检查 JSON 格式
    if [[ "$sbom_file" == *.json ]]; then
        if command -v jq &> /dev/null; then
            if jq empty "$sbom_file" 2>/dev/null; then
                log_success "SBOM JSON 格式验证通过"
                
                # 统计组件数量
                local component_count=$(jq '.components | length' "$sbom_file")
                log_info "组件数量: $component_count"
            else
                log_error "SBOM JSON 格式无效"
                return 1
            fi
        else
            log_warn "未安装 jq，跳过 JSON 验证"
        fi
    fi
    
    return 0
}

# 生成 SBOM 摘要报告
generate_summary() {
    log_info "生成 SBOM 摘要报告..."
    
    local summary_file="$OUTPUT_DIR/sbom-summary.txt"
    
    echo "========================================" > "$summary_file"
    echo "SBOM 生成报告" >> "$summary_file"
    echo "========================================" >> "$summary_file"
    echo "" >> "$summary_file"
    echo "项目信息:" >> "$summary_file"
    echo "  名称: $PROJECT_NAME" >> "$summary_file"
    echo "  版本: $PROJECT_VERSION" >> "$summary_file"
    echo "  类型: $PROJECT_TYPE" >> "$summary_file"
    echo "" >> "$summary_file"
    echo "生成时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$summary_file"
    echo "" >> "$summary_file"
    echo "生成的文件:" >> "$summary_file"
    
    for file in "$OUTPUT_DIR"/*; do
        if [ -f "$file" ]; then
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
            local size_human=""
            
            if [ "$size" -lt 1024 ]; then
                size_human="${size}B"
            elif [ "$size" -lt 1048576 ]; then
                size_human="$(echo "scale=2; $size/1024" | bc)KB"
            else
                size_human="$(echo "scale=2; $size/1048576" | bc)MB"
            fi
            
            echo "  - $(basename "$file") ($size_human)" >> "$summary_file"
        fi
    done
    
    echo "" >> "$summary_file"
    echo "========================================" >> "$summary_file"
    
    log_success "摘要报告已生成: $summary_file"
    cat "$summary_file"
}

# 主函数
main() {
    log_info "SBOM 生成工具"
    log_info "===================="
    
    # 解析参数
    parse_args "$@"
    
    # 检查依赖
    check_dependencies
    
    # 检测项目类型
    detect_project_type
    
    # 获取项目信息
    get_project_info
    
    # 根据项目类型生成 SBOM
    case $PROJECT_TYPE in
        maven)
            generate_maven_sbom
            ;;
        go)
            generate_go_sbom
            ;;
        nodejs)
            generate_nodejs_sbom
            ;;
        *)
            log_error "不支持的项目类型: $PROJECT_TYPE"
            exit 1
            ;;
    esac
    
    # 验证生成的 SBOM
    for sbom_file in "$OUTPUT_DIR"/*.json "$OUTPUT_DIR"/*.xml; do
        if [ -f "$sbom_file" ]; then
            validate_sbom "$sbom_file"
        fi
    done
    
    # 生成摘要报告
    generate_summary
    
    log_success "SBOM 生成完成!"
    log_info "输出目录: $OUTPUT_DIR"
}

# 运行主函数
main "$@"
