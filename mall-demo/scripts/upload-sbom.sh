#!/bin/bash
#
# SBOM 上传脚本
# 支持上传到 Harbor、专用存储或 GitLab Artifacts
#
# 使用方法:
#   ./upload-sbom.sh [选项]
#
# 选项:
#   -f, --file <path>        SBOM 文件路径 (必需)
#   -t, --target <target>    上传目标: harbor|gitlab|s3|artifactory (默认: harbor)
#   -u, --url <url>          目标服务器 URL
#   -p, --project <name>     Harbor 项目名称
#   -r, --repo <name>        Harbor 仓库名称
#   -a, --artifact <tag>     镜像标签/版本
#   -k, --token <token>      认证令牌
#   -h, --help               显示帮助信息
#
# 示例:
#   # 上传到 Harbor
#   ./upload-sbom.sh -f ./sbom.json -t harbor -u https://harbor.example.com -p mall-demo -r user-service -a v1.0.0
#
#   # 上传到 GitLab
#   ./upload-sbom.sh -f ./sbom.json -t gitlab -u https://gitlab.example.com -p 123 -k $CI_JOB_TOKEN
#
#   # 上传到 S3
#   ./upload-sbom.sh -f ./sbom.json -t s3 -u s3://my-bucket/sbom/
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置
SBOM_FILE=""
TARGET="harbor"
TARGET_URL=""
PROJECT_NAME=""
REPO_NAME=""
ARTIFACT_TAG=""
TOKEN=""

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
    head -n 25 "$0" | tail -n 23
}

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                SBOM_FILE="$2"
                shift 2
                ;;
            -t|--target)
                TARGET="$2"
                shift 2
                ;;
            -u|--url)
                TARGET_URL="$2"
                shift 2
                ;;
            -p|--project)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -r|--repo)
                REPO_NAME="$2"
                shift 2
                ;;
            -a|--artifact)
                ARTIFACT_TAG="$2"
                shift 2
                ;;
            -k|--token)
                TOKEN="$2"
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

# 验证参数
validate_args() {
    if [ -z "$SBOM_FILE" ]; then
        log_error "必须指定 SBOM 文件路径 (-f)"
        exit 1
    fi
    
    if [ ! -f "$SBOM_FILE" ]; then
        log_error "SBOM 文件不存在: $SBOM_FILE"
        exit 1
    fi
    
    if [ -z "$TARGET_URL" ]; then
        # 尝试从环境变量获取
        case $TARGET in
            harbor)
                TARGET_URL="${HARBOR_URL:-}"
                ;;
            gitlab)
                TARGET_URL="${CI_API_V4_URL:-${GITLAB_URL:-}}"
                ;;
            s3)
                TARGET_URL="${S3_BUCKET:-}"
                ;;
            artifactory)
                TARGET_URL="${ARTIFACTORY_URL:-}"
                ;;
        esac
        
        if [ -z "$TARGET_URL" ]; then
            log_error "必须指定目标服务器 URL (-u)"
            exit 1
        fi
    fi
    
    # 从环境变量获取其他参数
    if [ -z "$TOKEN" ]; then
        case $TARGET in
            harbor)
                TOKEN="${HARBOR_TOKEN:-${HARBOR_PASSWORD:-}}"
                ;;
            gitlab)
                TOKEN="${CI_JOB_TOKEN:-${GITLAB_TOKEN:-}}"
                ;;
        esac
    fi
    
    if [ -z "$PROJECT_NAME" ]; then
        PROJECT_NAME="${CI_PROJECT_NAME:-${HARBOR_PROJECT:-}}"
    fi
    
    if [ -z "$REPO_NAME" ]; then
        REPO_NAME="${CI_PROJECT_NAME:-}"
    fi
    
    if [ -z "$ARTIFACT_TAG" ]; then
        ARTIFACT_TAG="${CI_COMMIT_TAG:-${CI_COMMIT_SHA:-latest}}"
    fi
}

# 从 SBOM 文件提取信息
extract_sbom_info() {
    local sbom_file=$1
    
    if command -v jq &> /dev/null; then
        SBOM_FORMAT=$(jq -r '.bomFormat // "unknown"' "$sbom_file" 2>/dev/null || echo "unknown")
        SBOM_VERSION=$(jq -r '.specVersion // "unknown"' "$sbom_file" 2>/dev/null || echo "unknown")
        COMPONENT_COUNT=$(jq '.components | length' "$sbom_file" 2>/dev/null || echo "0")
        
        log_info "SBOM 信息:"
        log_info "  格式: $SBOM_FORMAT"
        log_info "  版本: $SBOM_VERSION"
        log_info "  组件数: $COMPONENT_COUNT"
    else
        log_warn "未安装 jq，无法解析 SBOM 信息"
    fi
}

# 上传到 Harbor
upload_to_harbor() {
    log_info "上传到 Harbor..."
    
    if [ -z "$PROJECT_NAME" ] || [ -z "$REPO_NAME" ] || [ -z "$ARTIFACT_TAG" ]; then
        log_error "Harbor 上传需要指定项目 (-p)、仓库 (-r) 和标签 (-a)"
        exit 1
    fi
    
    local sbom_filename=$(basename "$SBOM_FILE")
    local mime_type="application/vnd.cyclonedx+json"
    
    if [[ "$SBOM_FILE" == *.xml ]]; then
        mime_type="application/vnd.cyclonedx+xml"
    elif [[ "$SBOM_FILE" == *.spdx* ]]; then
        mime_type="application/spdx+json"
    fi
    
    # Harbor API 端点
    local api_url="${TARGET_URL}/api/v2.0/projects/${PROJECT_NAME}/repositories/${REPO_NAME}/artifacts/${ARTIFACT_TAG}/accessories"
    
    log_info "API URL: $api_url"
    
    # 上传 SBOM 作为镜像附件
    local response
    if [ -n "$TOKEN" ]; then
        response=$(curl -s -w "\n%{http_code}" -X POST "$api_url" \
            -H "Content-Type: $mime_type" \
            -H "Authorization: Bearer $TOKEN" \
            --data-binary "@$SBOM_FILE" 2>&1) || true
    else
        log_warn "未提供认证令牌，尝试匿名上传..."
        response=$(curl -s -w "\n%{http_code}" -X POST "$api_url" \
            -H "Content-Type: $mime_type" \
            --data-binary "@$SBOM_FILE" 2>&1) || true
    fi
    
    local http_code=$(echo "$response" | tail -n 1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "201" ] || [ "$http_code" = "200" ]; then
        log_success "SBOM 成功上传到 Harbor"
        log_info "访问地址: ${TARGET_URL}/harbor/projects/${PROJECT_NAME}/repositories/${REPO_NAME}/artifacts-tab/artifacts/${ARTIFACT_TAG}"
    else
        log_error "上传失败 (HTTP $http_code)"
        log_error "响应: $body"
        
        # 尝试替代方法：直接推送为 artifact
        log_info "尝试使用替代方法上传..."
        upload_to_harbor_alternative
    fi
}

# Harbor 替代上传方法
upload_to_harbor_alternative() {
    log_info "使用 ORAS 上传 SBOM..."
    
    # 检查 oras 是否安装
    if ! command -v oras &> /dev/null; then
        log_error "未找到 oras 工具，请先安装: https://oras.land/cli/"
        exit 1
    fi
    
    local sbom_filename=$(basename "$SBOM_FILE")
    local target_artifact="${TARGET_URL}/${PROJECT_NAME}/${REPO_NAME}:${ARTIFACT_TAG}.sbom"
    
    if [ -n "$TOKEN" ]; then
        oras push --username "robot\$sbom-uploader" --password "$TOKEN" \
            "$target_artifact" \
            "application/vnd.cyclonedx+json:$SBOM_FILE"
    else
        oras push "$target_artifact" \
            "application/vnd.cyclonedx+json:$SBOM_FILE"
    fi
    
    log_success "SBOM 成功上传到: $target_artifact"
}

# 上传到 GitLab
upload_to_gitlab() {
    log_info "上传到 GitLab..."
    
    if [ -z "$PROJECT_NAME" ]; then
        log_error "GitLab 上传需要指定项目 ID (-p)"
        exit 1
    fi
    
    local sbom_filename=$(basename "$SBOM_FILE")
    local api_url="${TARGET_URL}/projects/${PROJECT_NAME}/packages/generic/sbom/${ARTIFACT_TAG}/${sbom_filename}"
    
    log_info "API URL: $api_url"
    
    local response
    if [ -n "$TOKEN" ]; then
        response=$(curl -s -w "\n%{http_code}" --upload-file "$SBOM_FILE" \
            --header "PRIVATE-TOKEN: $TOKEN" \
            "$api_url" 2>&1) || true
    else
        log_error "GitLab 上传需要提供访问令牌 (-k)"
        exit 1
    fi
    
    local http_code=$(echo "$response" | tail -n 1)
    
    if [ "$http_code" = "201" ]; then
        log_success "SBOM 成功上传到 GitLab Package Registry"
    else
        log_error "上传失败 (HTTP $http_code)"
        exit 1
    fi
}

# 上传到 S3
upload_to_s3() {
    log_info "上传到 S3..."
    
    if ! command -v aws &> /dev/null; then
        log_error "未找到 AWS CLI，请先安装"
        exit 1
    fi
    
    local sbom_filename=$(basename "$SBOM_FILE")
    local s3_path="${TARGET_URL%/}/${sbom_filename}"
    
    # 添加元数据
    local metadata=""
    if command -v jq &> /dev/null; then
        local project=$(jq -r '.metadata.component.name // "unknown"' "$SBOM_FILE" 2>/dev/null || echo "unknown")
        local version=$(jq -r '.metadata.component.version // "unknown"' "$SBOM_FILE" 2>/dev/null || echo "unknown")
        
        metadata="--metadata project=$project,version=$version,uploaded=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi
    
    aws s3 cp "$SBOM_FILE" "$s3_path" $metadata
    
    log_success "SBOM 成功上传到: $s3_path"
}

# 上传到 Artifactory
upload_to_artifactory() {
    log_info "上传到 Artifactory..."
    
    local sbom_filename=$(basename "$SBOM_FILE")
    local repo_path="${TARGET_URL%/}/${PROJECT_NAME}/${REPO_NAME}/${ARTIFACT_TAG}/${sbom_filename}"
    
    local headers=()
    headers+=("Content-Type: application/json")
    
    if [ -n "$TOKEN" ]; then
        headers+=("Authorization: Bearer $TOKEN")
    fi
    
    local header_args=""
    for header in "${headers[@]}"; do
        header_args="$header_args -H '$header'"
    done
    
    eval curl -s -f -X PUT $header_args --data-binary "@$SBOM_FILE" "$repo_path"
    
    log_success "SBOM 成功上传到: $repo_path"
}

# 保存为 GitLab CI Artifact
save_gitlab_artifact() {
    log_info "保存为 GitLab CI Artifact..."
    
    # 创建 artifacts 目录
    mkdir -p sbom-artifacts
    cp "$SBOM_FILE" "sbom-artifacts/"
    
    # 生成元数据文件
    cat > sbom-artifacts/metadata.json << EOF
{
    "project": "$PROJECT_NAME",
    "version": "$ARTIFACT_TAG",
    "uploaded_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "sbom_file": "$(basename "$SBOM_FILE")"
}
EOF
    
    log_success "SBOM 已准备为 GitLab CI Artifact"
    log_info "请在 .gitlab-ci.yml 中配置 artifacts:paths: - sbom-artifacts/"
}

# 生成上传报告
generate_upload_report() {
    local target=$1
    local url=$2
    
    local report_file="sbom-upload-report.txt"
    
    echo "========================================" > "$report_file"
    echo "SBOM 上传报告" >> "$report_file"
    echo "========================================" >> "$report_file"
    echo "" >> "$report_file"
    echo "上传信息:" >> "$report_file"
    echo "  目标: $target" >> "$report_file"
    echo "  URL: $url" >> "$report_file"
    echo "  项目: $PROJECT_NAME" >> "$report_file"
    echo "  仓库: $REPO_NAME" >> "$report_file"
    echo "  版本: $ARTIFACT_TAG" >> "$report_file"
    echo "" >> "$report_file"
    echo "SBOM 文件:" >> "$report_file"
    echo "  路径: $SBOM_FILE" >> "$report_file"
    echo "  大小: $(stat -f%z "$SBOM_FILE" 2>/dev/null || stat -c%s "$SBOM_FILE" 2>/dev/null) bytes" >> "$report_file"
    echo "" >> "$report_file"
    echo "上传时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$report_file"
    echo "========================================" >> "$report_file"
    
    log_success "上传报告已生成: $report_file"
    cat "$report_file"
}

# 主函数
main() {
    log_info "SBOM 上传工具"
    log_info "===================="
    
    # 解析参数
    parse_args "$@"
    
    # 验证参数
    validate_args
    
    # 提取 SBOM 信息
    extract_sbom_info "$SBOM_FILE"
    
    # 根据目标执行上传
    case $TARGET in
        harbor)
            upload_to_harbor
            generate_upload_report "Harbor" "${TARGET_URL}/harbor/projects/${PROJECT_NAME}/repositories/${REPO_NAME}"
            ;;
        gitlab)
            upload_to_gitlab
            generate_upload_report "GitLab" "${TARGET_URL}/projects/${PROJECT_NAME}/packages/generic/sbom"
            ;;
        s3)
            upload_to_s3
            generate_upload_report "S3" "$TARGET_URL"
            ;;
        artifactory)
            upload_to_artifactory
            generate_upload_report "Artifactory" "$TARGET_URL"
            ;;
        artifact)
            save_gitlab_artifact
            ;;
        *)
            log_error "不支持的上传目标: $TARGET"
            exit 1
            ;;
    esac
    
    log_success "SBOM 上传完成!"
}

# 运行主函数
main "$@"
