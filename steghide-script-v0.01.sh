#!/bin/bash

# ============================================================
#  SteghideGUI — Interface gráfica YAD para o Steghide
#  Autor: gerado com assistência do Claude
# ============================================================

APP_NAME="SteghideGUI"
ICON_INFO="dialog-information"
ICON_OK="dialog-ok"
ICON_ERR="dialog-error"
ICON_WARN="dialog-warning"

# ------------------------------------------------------------
# Função: verifica e instala uma dependência
# ------------------------------------------------------------
verificar_instalar() {
    local pkg="$1"
    local cmd="${2:-$1}"   # comando a testar (padrão = nome do pacote)

    if ! command -v "$cmd" &>/dev/null; then
        yad --title "$APP_NAME" \
            --image "$ICON_WARN" \
            --text "<b>$pkg</b> não está instalado.\n\nDeseja instalar agora?" \
            --button="Instalar:0" \
            --button="Cancelar:1" \
            --center --width=360 2>/dev/null

        if [ $? -eq 0 ]; then
            # Janela de progresso durante instalação
            (
                sudo apt-get update -qq 2>&1
                sudo apt-get install -y "$pkg" 2>&1
            ) | yad --progress \
                    --title "Instalando $pkg" \
                    --text "Aguarde, instalando <b>$pkg</b>..." \
                    --pulsate --auto-close --auto-kill \
                    --center --width=400 2>/dev/null

            if ! command -v "$cmd" &>/dev/null; then
                yad --title "$APP_NAME" \
                    --image "$ICON_ERR" \
                    --text "Falha ao instalar <b>$pkg</b>.\nVerifique suas permissões sudo e conexão." \
                    --button="Fechar:0" \
                    --center --width=360 2>/dev/null
                return 1
            fi

            yad --title "$APP_NAME" \
                --image "$ICON_OK" \
                --text "<b>$pkg</b> instalado com sucesso!" \
                --button="OK:0" \
                --center --width=300 2>/dev/null
        else
            return 1
        fi
    fi
    return 0
}

# ------------------------------------------------------------
# Verifica YAD primeiro (bootstrap sem GUI)
# ------------------------------------------------------------
if ! command -v yad &>/dev/null; then
    echo "YAD não encontrado. Instalando..."
    sudo apt-get update -qq && sudo apt-get install -y yad
    if ! command -v yad &>/dev/null; then
        echo "ERRO: Não foi possível instalar o YAD. Abortando."
        exit 1
    fi
fi

# Verifica steghide
verificar_instalar "steghide" "steghide" || exit 1

# ------------------------------------------------------------
# Função: menu principal
# ------------------------------------------------------------
menu_principal() {
    yad --title "$APP_NAME" \
        --image "gtk-dialog-authentication" \
        --text "<span font='14' weight='bold'>SteghideGUI</span>\n<span font='10' color='gray'>Esteganografia via interface gráfica</span>\n" \
        --button="🔒  Camuflar arquivo:10" \
        --button="🔓  Descamuflar arquivo:20" \
        --button="❌  Sair:99" \
        --center --width=400 --height=180 \
        --no-buttons 2>/dev/null

    # yad retorna o código do botão clicado via $?
    # mas com --button=label:código, precisamos capturar via saída
    # Usamos form vazio + botões para capturar o código de saída
    : # placeholder — ver lógica abaixo
}

# ------------------------------------------------------------
# Função: camuflar arquivo
# ------------------------------------------------------------
camuflar() {
    # Seleciona imagem de capa
    imagem=$(yad --file \
        --title "Selecione a IMAGEM de capa (jpg, bmp, wav...)" \
        --file-filter="Imagens e áudios | *.jpg *.jpeg *.bmp *.png *.wav" \
        --file-filter="Todos os arquivos | *" \
        --center 2>/dev/null)

    [ -z "$imagem" ] && return

    # Seleciona arquivo secreto
    secreto=$(yad --file \
        --title "Selecione o ARQUIVO a camuflar" \
        --file-filter="Todos os arquivos | *" \
        --center 2>/dev/null)

    [ -z "$secreto" ] && return

    # Diálogo "Salvar como" para o arquivo de saída
    saida=$(yad --file \
        --title "Salvar arquivo camuflado como..." \
        --save \
        --confirm-overwrite \
        --filename="${imagem%.*}_camuflado.${imagem##*.}" \
        --file-filter="JPEG | *.jpg *.jpeg" \
        --file-filter="BMP  | *.bmp" \
        --file-filter="WAV  | *.wav" \
        --file-filter="Todos os arquivos | *" \
        --center 2>/dev/null)

    [ -z "$saida" ] && return

    # Pede senha separadamente
    senha=$(yad --entry \
        --title "Senha de proteção" \
        --text "Digite uma senha para proteger o arquivo\n<span color='gray'>(deixe em branco para não usar senha)</span>:" \
        --hide-text \
        --button="Confirmar:0" \
        --button="Cancelar:1" \
        --center --width=400 2>/dev/null)

    [ $? -ne 0 ] && return

    # Monta comando
    if [ -n "$senha" ]; then
        CMD=(steghide embed -cf "$imagem" -ef "$secreto" -sf "$saida" -p "$senha" -f)
    else
        CMD=(steghide embed -cf "$imagem" -ef "$secreto" -sf "$saida" -p "" -f)
    fi

    # Executa e captura saída
    output=$("${CMD[@]}" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        yad --title "$APP_NAME" \
            --image "$ICON_OK" \
            --text "✅ <b>Arquivo camuflado com sucesso!</b>\n\nSalvo em:\n<tt>$saida</tt>" \
            --button="OK:0" \
            --center --width=460 2>/dev/null
    else
        yad --title "$APP_NAME" \
            --image "$ICON_ERR" \
            --text "❌ <b>Erro ao camuflar arquivo.</b>\n\nDetalhe:\n<tt>$output</tt>" \
            --button="Fechar:0" \
            --center --width=480 2>/dev/null
    fi
}

# ------------------------------------------------------------
# Função: descamuflar arquivo
# ------------------------------------------------------------
descamuflar() {
    # Seleciona imagem com arquivo escondido
    imagem=$(yad --file \
        --title "Selecione a IMAGEM que contém o arquivo camuflado" \
        --file-filter="Imagens e áudios | *.jpg *.jpeg *.bmp *.png *.wav" \
        --file-filter="Todos os arquivos | *" \
        --center 2>/dev/null)

    [ -z "$imagem" ] && return

    # Diálogo "Salvar como" para o arquivo extraído
    extraido=$(yad --file \
        --title "Salvar arquivo extraído como..." \
        --save \
        --confirm-overwrite \
        --filename="arquivo_extraido" \
        --file-filter="Texto        | *.txt *.csv *.md" \
        --file-filter="Imagens      | *.jpg *.jpeg *.png *.bmp *.gif" \
        --file-filter="Documentos   | *.pdf *.docx *.odt" \
        --file-filter="Compactados  | *.zip *.tar.gz *.7z" \
        --file-filter="Todos os arquivos | *" \
        --center 2>/dev/null)

    [ -z "$extraido" ] && return

    # Pede senha separadamente
    senha=$(yad --entry \
        --title "Senha do arquivo" \
        --text "Digite a senha do arquivo camuflado\n<span color='gray'>(deixe em branco se não tiver senha)</span>:" \
        --hide-text \
        --button="Confirmar:0" \
        --button="Cancelar:1" \
        --center --width=400 2>/dev/null)

    [ $? -ne 0 ] && return

    # Monta comando
    if [ -n "$senha" ]; then
        CMD=(steghide extract -sf "$imagem" -xf "$extraido" -p "$senha" -f)
    else
        CMD=(steghide extract -sf "$imagem" -xf "$extraido" -p "" -f)
    fi

    output=$("${CMD[@]}" 2>&1)
    exit_code=$?

    if [ $exit_code -eq 0 ]; then
        yad --title "$APP_NAME" \
            --image "$ICON_OK" \
            --text "✅ <b>Arquivo extraído com sucesso!</b>\n\nSalvo como:\n<tt>$extraido</tt>" \
            --button="OK:0" \
            --center --width=460 2>/dev/null
    else
        yad --title "$APP_NAME" \
            --image "$ICON_ERR" \
            --text "❌ <b>Erro ao extrair arquivo.</b>\n\nDetalhe:\n<tt>$output</tt>" \
            --button="Fechar:0" \
            --center --width=480 2>/dev/null
    fi
}

# ------------------------------------------------------------
# Loop principal
# ------------------------------------------------------------
while true; do
    escolha=$(yad --title "$APP_NAME" \
        --image "gtk-dialog-authentication" \
        --text "<span font='15' weight='bold'>🔐 SteghideGUI</span>\n<span font='10' color='gray'>Esteganografia com interface gráfica</span>\n\nEscolha uma ação:" \
        --list \
        --column="Opção" \
        "🔒  Camuflar arquivo" \
        "🔓  Descamuflar arquivo" \
        --button="Selecionar:0" \
        --button="Sair:1" \
        --center --width=420 --height=250 2>/dev/null)

    codigo=$?

    # Botão "Sair" ou fechou a janela
    if [ $codigo -ne 0 ]; then
        yad --title "$APP_NAME" \
            --image "$ICON_INFO" \
            --text "Até mais! 👋" \
            --button="OK:0" \
            --center --width=260 --timeout=2 2>/dev/null
        break
    fi

    case "$escolha" in
        *Camuflar*)    camuflar    ;;
        *Descamuflar*) descamuflar ;;
    esac
done
