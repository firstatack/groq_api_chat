#!/bin/bash

# Configuración básica
API_KEY="PEGA AQUI TU APY KEY"  # 🔑 Tu clave API_KEY
API_URL="https://api.groq.com/openai/v1/chat/completions"
MODELS_API_URL="https://api.groq.com/openai/v1/models"
CHATS_DIR="$HOME/.groq_chats"
CONFIG_FILE="$HOME/.groq_config"
MODELS_CACHE_FILE="$CHATS_DIR/models.cache"
MODELS_CACHE_DAYS=7  # Actualizar caché cada 7 días

# Colores para mejor visualización
GREEN='\033[1;32m'
BLUE='\033[1;34m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
PURPLE='\033[1;35m'
NC='\033[0m'  # Sin color

# Crear directorio de chats si no existe
mkdir -p "$CHATS_DIR"

# Cargar configuración o inicializar con valores por defecto
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
    else
        # Configuración por defecto
        DEFAULT_MODEL="meta-llama/llama-4-scout-17b-16e-instruct"
        DEFAULT_TEMPERATURE="0.7"
        DEFAULT_MAX_TOKENS="4096"
        save_config
    fi
}

# Guardar configuración
save_config() {
    cat > "$CONFIG_FILE" <<EOL
DEFAULT_MODEL="$DEFAULT_MODEL"
DEFAULT_TEMPERATURE="$DEFAULT_TEMPERATURE"
DEFAULT_MAX_TOKENS="$DEFAULT_MAX_TOKENS"
EOL
}

# Función para actualizar la caché de modelos
update_models_cache() {
    echo -e "${YELLOW}Actualizando lista de modelos disponibles...${NC}"
    
    local api_response=$(curl -s -X GET "$MODELS_API_URL" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" 2>/dev/null)
    
    if [[ $(echo "$api_response" | jq -r '.error?') != "null" ]] || [[ -z "$api_response" ]]; then
        echo -e "${RED}Error al obtener modelos de la API${NC}" >&2
        return 1
    fi
    
    # Procesar y guardar modelos con formato índice:modelo
    echo "$api_response" | jq -r '.data[].id' | awk '{print NR":"$0}' > "$MODELS_CACHE_FILE"
    
    declare -gA MODELS=()
    while IFS=':' read -r index model; do
        MODELS["$index"]="$model"
    done < "$MODELS_CACHE_FILE"
}

# Función para cargar modelos
load_models() {
    declare -gA MODELS=()
    
    # Valores por defecto como respaldo
    local default_models=(
        "meta-llama/llama-4-scout-17b-16e-instruct"
        "qwen/qwen3-32b"
        "openai/gpt-oss-120b"
        "gemma2-9b-it"
        "deepseek-r1-distill-llama-70b"
    )
    
    # Intentar cargar desde caché o API
    if [[ ! -f "$MODELS_CACHE_FILE" ]] || \
       [[ $(find "$MODELS_CACHE_FILE" -mtime +$MODELS_CACHE_DAYS 2>/dev/null) ]]; then
        if ! update_models_cache; then
            # Si falla, usar valores por defecto
            for i in "${!default_models[@]}"; do
                MODELS["$((i+1))"]="${default_models[$i]}"
            done
            echo -e "${YELLOW}Usando modelos por defecto${NC}"
            return 1
        fi
    else
        # Cargar desde caché
        while IFS=':' read -r index model; do
            MODELS["$index"]="$model"
        done < "$MODELS_CACHE_FILE" 2>/dev/null
        
        # Verificar que se cargaron modelos
        if [[ ${#MODELS[@]} -eq 0 ]]; then
            for i in "${!default_models[@]}"; do
                MODELS["$((i+1))"]="${default_models[$i]}"
            done
            echo -e "${YELLOW}Usando modelos por defecto (caché vacío)${NC}"
        fi
    fi
}

# Mostrar menú principal
show_main_menu() {
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════╗"
    echo -e "${PURPLE}║          ${CYAN}GROQ API CHAT ${PURPLE}v2.0          ║"
    echo -e "${PURPLE}╠════════════════════════════════════════╣"
    echo -e "${PURPLE}║ ${GREEN}1. Nuevo chat                          ${PURPLE}║"
    echo -e "${PURPLE}║ ${GREEN}2. Buscar/Cargar chat                  ${PURPLE}║"
    echo -e "${PURPLE}║ ${GREEN}3. Configuración                       ${PURPLE}║"
    echo -e "${PURPLE}║ ${GREEN}4. Borrar chats                        ${PURPLE}║"
    echo -e "${PURPLE}║ ${GREEN}5. Pregunta rápida (flag -q)           ${PURPLE}║"
    echo -e "${PURPLE}║ ${RED}6. Salir                               ${PURPLE}║"
    echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Selecciona una opción (1-6):${NC} "
}

# Mostrar menú de selección de modelo
show_model_menu() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════╗"
    echo -e "${CYAN}║          ${PURPLE}SELECCIÓN DE MODELO AI${CYAN}          ║"
    echo -e "${CYAN}╠════════════════════════════════════════╣"
    
    # Ordenar las claves numéricamente
    local sorted_keys=($(printf '%s\n' "${!MODELS[@]}" | sort -n))
    
    for key in "${sorted_keys[@]}"; do
        echo -e "${CYAN}║ ${GREEN}$key. ${YELLOW}${MODELS[$key]}${CYAN}"
    done
    
    echo -e "${CYAN}╠════════════════════════════════════════╣"
    echo -e "${CYAN}║ ${GREEN}r. Actualizar lista de modelos       ${CYAN}║"
    echo -e "${CYAN}║ ${RED}q. Volver al menú principal         ${CYAN}║"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Selecciona un modelo (1-${#MODELS[@]}):${NC} "
}

# Seleccionar modelo
select_model() {
    while true; do
        show_model_menu
        read -p "" choice
        
        case "$choice" in
            [1-9]*)  # Cualquier número
                if [[ -n "${MODELS[$choice]}" ]]; then
                    MODEL="${MODELS[$choice]}"
                    echo -e "\n${GREEN}Modelo seleccionado: ${YELLOW}$MODEL${NC}\n"
                    return 0
                else
                    echo -e "${RED}Opción inválida. Intenta nuevamente.${NC}"
                    sleep 2
                fi
                ;;
            r|R)
                if update_models_cache; then
                    echo -e "${GREEN}Lista de modelos actualizada correctamente.${NC}"
                    sleep 1
                else
                    echo -e "${YELLOW}No se pudo actualizar. Usando lista existente.${NC}"
                    sleep 2
                fi
                ;;
            q|Q)
                return 1
                ;;
            *)
                echo -e "${RED}Opción inválida. Intenta nuevamente.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Mostrar menú de configuración
show_config_menu() {
    clear
    echo -e "${PURPLE}╔════════════════════════════════════════╗"
    echo -e "${PURPLE}║           ${CYAN}CONFIGURACIÓN${PURPLE}                ║"
    echo -e "${PURPLE}╠════════════════════════════════════════╣"
    echo -e "${PURPLE}║ ${GREEN}1. Modelo por defecto: ${YELLOW}$DEFAULT_MODEL${PURPLE} ║"
    echo -e "${PURPLE}║ ${GREEN}2. Temperatura: ${YELLOW}$DEFAULT_TEMPERATURE${PURPLE}            ║"
    echo -e "${PURPLE}║ ${GREEN}3. Máximo de tokens: ${YELLOW}$DEFAULT_MAX_TOKENS${PURPLE}        ║"
    echo -e "${PURPLE}║ ${RED}4. Volver al menú principal${PURPLE}           ║"
    echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Selecciona una opción (1-4):${NC} "
}

# Mostrar menú de chat
show_chat_header() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════╗"
    echo -e "${CYAN}║ ${PURPLE}Chat: ${YELLOW}${chat_name:-Nuevo chat}${PURPLE} Modelo: ${YELLOW}$MODEL${CYAN} ║"
    echo -e "${CYAN}╠════════════════════════════════════════╣"
    echo -e "${CYAN}║ ${GREEN}/guardar ${PURPLE}- ${GREEN}Guardar chat  ${PURPLE}| ${GREEN}/menu ${PURPLE}- ${GREEN}Menú principal${CYAN} ║"
    echo -e "${CYAN}║ ${RED}/salir ${PURPLE}- ${RED}Salir ${PURPLE}| ${GREEN}/ayuda ${PURPLE}- ${GREEN}Mostrar ayuda${CYAN} ║"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# Mostrar ayuda completa del chat
show_chat_help() {
    show_chat_header
    echo -e "${PURPLE}╔════════════════════════════════════════╗"
    echo -e "${PURPLE}║             ${CYAN}AYUDA DEL CHAT${PURPLE}              ║"
    echo -e "${PURPLE}╠════════════════════════════════════════╣"
    echo -e "${PURPLE}║ ${GREEN}/guardar ${PURPLE}- Guarda el chat actual          ${PURPLE}║"
    echo -e "${PURPLE}║ ${GREEN}/menu ${PURPLE}- Vuelve al menú principal         ${PURPLE}║"
    echo -e "${PURPLE}║ ${RED}/salir ${PURPLE}- Sale del programa               ${PURPLE}║"
    echo -e "${PURPLE}║ ${GREEN}/modelo ${PURPLE}- Muestra el modelo actual       ${PURPLE}║"
    echo -e "${PURPLE}║ ${GREEN}/ayuda ${PURPLE}- Muestra esta ayuda             ${PURPLE}║"
    echo -e "${PURPLE}╚════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Presiona Enter para continuar...${NC}"
    read
}

# Configurar opciones
configure_settings() {
    while true; do
        show_config_menu
        read -p "" choice
        
        case $choice in
            1)
                if select_model; then
                    DEFAULT_MODEL="$MODEL"
                    save_config
                    echo -e "${GREEN}Modelo por defecto actualizado.${NC}"
                    sleep 2
                fi
                ;;
            2)
                read -p "Nueva temperatura (0.1-2.0): " DEFAULT_TEMPERATURE
                save_config
                echo -e "${GREEN}Temperatura actualizada.${NC}"
                sleep 2
                ;;
            3)
                read -p "Nuevo máximo de tokens (1-4096): " DEFAULT_MAX_TOKENS
                save_config
                echo -e "${GREEN}Máximo de tokens actualizado.${NC}"
                sleep 2
                ;;
            4)
                return
                ;;
            *)
                echo -e "${RED}Opción inválida. Intenta nuevamente.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Listar chats existentes
list_chats() {
    clear
    echo -e "${CYAN}╔════════════════════════════════════════╗"
    echo -e "${CYAN}║          ${PURPLE}CHATS GUARDADOS${CYAN}               ║"
    echo -e "${CYAN}╠════════════════════════════════════════╣"
    
    local chats=("$CHATS_DIR"/*.chat)
    if [[ ${#chats[@]} -eq 0 || ! -f "${chats[0]}" ]]; then
        echo -e "${CYAN}║ ${YELLOW}No hay chats guardados${CYAN}                 ║"
    else
        for i in "${!chats[@]}"; do
            chat_name=$(basename "${chats[$i]}" .chat)
            echo -e "${CYAN}║ ${GREEN}$((i+1)). ${YELLOW}$chat_name${CYAN}${NC}"
        done
    fi
    
    echo -e "${CYAN}╠════════════════════════════════════════╣"
    echo -e "${CYAN}║ ${RED}0. Volver al menú principal${CYAN}             ║"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo -e "${YELLOW}Selecciona un chat para cargar (1-${#chats[@]}):${NC} "
}

# Cargar chat
load_chat() {
    list_chats
    local chats=("$CHATS_DIR"/*.chat)
    
    if [[ ${#chats[@]} -eq 0 || ! -f "${chats[0]}" ]]; then
        read -p "Presiona Enter para continuar..."
        return 1
    fi
    
    read -p "" choice
    
    if [[ "$choice" =~ [qQ0] ]]; then
        return 1
    fi
    
    if [[ "$choice" -ge 1 && "$choice" -le ${#chats[@]} ]]; then
        selected_chat="${chats[$((choice-1))]}"
        chat_name=$(basename "$selected_chat" .chat)
        
        # Extraer modelo y mensajes del chat
        MODEL=$(jq -r '.model' "$selected_chat")
        messages=$(jq '.messages' "$selected_chat")
        
        # Preparar el historial del chat para chat_loop
        chat_history=()
        while IFS= read -r line; do
            if [[ "$line" == *'"role": "user"'* ]]; then
                content=$(echo "$line" | jq -r '.content')
                chat_history+=("$content")
            elif [[ "$line" == *'"role": "assistant"'* ]]; then
                content=$(echo "$line" | jq -r '.content')
                chat_history+=("$content")
            fi
        done < <(echo "$messages" | jq -c '.[]')
        
        echo -e "\n${GREEN}Chat '${YELLOW}$chat_name${GREEN}' cargado correctamente.${NC}"
        echo -e "${CYAN}Modelo: ${YELLOW}$MODEL${NC}\n"
        return 0
    else
        echo -e "${RED}Opción inválida.${NC}"
        sleep 2
        return 1
    fi
}

# Borrar chats
delete_chats() {
    while true; do
        list_chats
        local chats=("$CHATS_DIR"/*.chat)
        
        if [[ ${#chats[@]} -eq 0 || ! -f "${chats[0]}" ]]; then
            read -p "Presiona Enter para continuar..."
            return
        fi
        
        read -p "Selecciona chat a borrar (1-${#chats[@]}) o 0: " choice
        
        if [[ "$choice" =~ [0] ]]; then
            return
        fi
        
        if [[ "$choice" -ge 1 && "$choice" -le ${#chats[@]} ]]; then
            selected_chat="${chats[$((choice-1))]}"
            chat_name=$(basename "$selected_chat" .chat)
            
            read -p "¿Borrar '${chat_name}'? (s/n): " confirm
            if [[ "$confirm" =~ [sSyY] ]]; then
                rm "$selected_chat"
                echo -e "${GREEN}Chat '${YELLOW}$chat_name${GREEN}' borrado.${NC}"
                sleep 2
            fi
        else
            echo -e "${RED}Opción inválida.${NC}"
            sleep 2
        fi
    done
}

# Guardar chat
save_chat() {
    if [[ -z "$chat_name" ]]; then
        read -p "Nombre para este chat: " chat_name
    fi
    
    chat_file="$CHATS_DIR/$chat_name.chat"
    
    # Crear JSON con la conversación
    echo '{"model": "'"$MODEL"'", "messages": []}' > "$chat_file"
    
    # Agregar cada mensaje
    for ((i=0; i<${#chat_history[@]}; i++)); do
        role=$([[ $((i%2)) -eq 0 ]] && echo "user" || echo "assistant")
        content="${chat_history[$i]}"
        
        jq --arg role "$role" \
           --arg content "$content" \
           '.messages += [{"role": $role, "content": $content}]' \
           "$chat_file" > temp && mv temp "$chat_file"
    done
    
    echo -e "${GREEN}Chat guardado como '${YELLOW}$chat_name${GREEN}'.${NC}"
    sleep 2
}

# Función para probar conexión
test_connection() {
    echo -e "${YELLOW}Probando conexión con Groq API...${NC}"
    response=$(curl -s -X POST "$API_URL" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$MODEL"'",
            "messages": [{"role": "user", "content": "Hola"}],
            "max_tokens": 5
        }')
    
    if [[ $(echo "$response" | jq -r '.choices[0].message.content') != "null" ]]; then
        echo -e "${GREEN}✓ Conexión exitosa${NC}\n"
        return 0
    else
        echo -e "${RED}✗ Error de conexión${NC}"
        echo -e "${YELLOW}Respuesta cruda:${NC}\n$response"
        return 1
    fi
}

# Función para llamar a la API
call_api() {
    local user_input="$1"
    
    # Construir el array de mensajes para la API
    local api_messages='[]'
    for ((i=0; i<${#chat_history[@]}; i++)); do
        role=$([[ $((i%2)) -eq 0 ]] && echo "user" || echo "assistant")
        content="${chat_history[$i]}"
        api_messages=$(echo "$api_messages" | jq --arg role "$role" --arg content "$content" '. += [{"role": $role, "content": $content}]')
    done
    
    # Agregar el nuevo mensaje del usuario
    api_messages=$(echo "$api_messages" | jq --arg content "$user_input" '. += [{"role": "user", "content": $content}]')
    
    curl -s -X POST "$API_URL" \
        -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        -d '{
            "model": "'"$MODEL"'",
            "messages": '"$api_messages"',
            "temperature": '"$DEFAULT_TEMPERATURE"',
            "max_tokens": '"$DEFAULT_MAX_TOKENS"'
        }'
}

# Función para formatear código
format_code() {
    local code="$1"
    if command -v pygmentize &>/dev/null; then
        echo -e "$code" | pygmentize -l python -O style=monokai
    elif command -v highlight &>/dev/null; then
        echo -e "$code" | highlight --syntax=python --out-format=ansi
    else
        echo -e "${YELLOW}$code${NC}"
    fi
}

# Pregunta rápida con flag -q
quick_question() {
    if [[ -z "$1" ]]; then
        echo -e "${RED}Error: No se proporcionó una pregunta.${NC}"
        echo -e "${YELLOW}Uso: $0 -q \"Tu pregunta\"${NC}"
        exit 1
    fi
    
    MODEL="$DEFAULT_MODEL"
    echo -e "${CYAN}Pregunta rápida usando modelo por defecto ($MODEL)${NC}\n"
    echo -e "${BLUE}>> Tú: ${YELLOW}$1${NC}"
    
    response=$(call_api "$1")
    content=$(echo "$response" | jq -r '.choices[0].message.content')
    
    echo -e "\n${GREEN}🤖 Respuesta:${NC}"
    if [[ "$content" == *'```'* ]]; then
        while IFS= read -r line; do
            if [[ "$line" == *'```'* ]]; then
                echo -e "${YELLOW}$line${NC}"
            else
                format_code "$line"
            fi
        done <<< "$content"
    else
        echo -e "$content"
    fi
    echo ""
    exit 0
}

# Bucle principal del chat
chat_loop() {
    show_chat_header
    
    # Mostrar historial si existe
    if [[ ${#chat_history[@]} -gt 0 ]]; then
        echo -e "${PURPLE}Historial del chat:${NC}"
        for ((i=0; i<${#chat_history[@]}; i++)); do
            if [[ $((i%2)) -eq 0 ]]; then
                echo -e "${BLUE}>> Tú: ${YELLOW}${chat_history[$i]}${NC}"
            else
                echo -e "${GREEN}🤖 Respuesta: ${YELLOW}${chat_history[$i]}${NC}"
            fi
        done
        echo ""
    fi
    
    while true; do
        echo -e "${BLUE}>> Tú: (Escribe tu mensaje y presiona Ctrl+D cuando termines)${NC}"
        
        # Leer múltiples líneas hasta EOF (Ctrl+D)
        user_input=$(cat)
        
        # Eliminar espacios en blanco al inicio/final
        user_input=$(echo "$user_input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        
        # Comandos especiales
        case $user_input in
            "/salir")
                echo -e "${GREEN}¡Hasta luego!${NC}"
                exit 0
                ;;
            "/modelo")
                echo -e "${CYAN}Modelo actual: ${YELLOW}$MODEL${NC}"
                continue
                ;;
            "/menu")
                return
                ;;
            "/guardar")
                save_chat
                show_chat_header
                continue
                ;;
            "/ayuda")
                show_chat_help
                show_chat_header
                continue
                ;;
            "")
                echo -e "${YELLOW}No se ingresó texto. Intenta nuevamente.${NC}"
                continue
                ;;
        esac

        # Agregar a historial
        chat_history+=("$user_input")
        
        # Llamar a la API y mostrar respuesta
        echo -e "\n${GREEN}🤖 Respuesta:${NC}"
        response=$(call_api "$user_input")
        
        # Extraer el contenido de la respuesta
        content=$(echo "$response" | jq -r '.choices[0].message.content')
        
        # Manejar errores
        if [[ "$content" == "null" || -z "$content" ]]; then
            echo -e "${RED}Error: No se recibió respuesta válida${NC}"
            echo -e "${YELLOW}Respuesta cruda para debug:${NC}\n$response"
        else
            # Agregar respuesta al historial
            chat_history+=("$content")
            
            # Formatear código si existe en la respuesta
            if [[ "$content" == *'```'* ]]; then
                while IFS= read -r line; do
                    if [[ "$line" == *'```'* ]]; then
                        echo -e "${YELLOW}$line${NC}"
                    else
                        format_code "$line"
                    fi
                done <<< "$content"
            else
                echo -e "$content"
            fi
        fi
        echo ""
    done
}

# Menú principal
main_menu() {
    load_config
    load_models  # Cargar modelos al iniciar
    
    # Manejar pregunta rápida con flag -q
    if [[ "$1" == "-q" ]]; then
        shift
        quick_question "$@"
    fi
    
    while true; do
        show_main_menu
        read -p "" choice
        
        case $choice in
            1)
                if select_model; then
                    chat_name=""
                    chat_history=()
                    if test_connection; then
                        chat_loop
                    fi
                fi
                ;;
            2)
                if load_chat; then
                    if test_connection; then
                        chat_loop
                    fi
                fi
                ;;
            3)
                configure_settings
                ;;
            4)
                delete_chats
                ;;
            5)
                read -p "Introduce tu pregunta: " question
                quick_question "$question"
                ;;
            6)
                echo -e "${GREEN}¡Hasta luego!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Opción inválida. Intenta nuevamente.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Iniciar programa
main_menu "$@"
