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

# Verifica ImageMagick (para converter imagens incompatíveis)
verificar_instalar "imagemagick" "convert" || exit 1

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
        --filename="${imagem%.*}_camuflado.jpg" \
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

    # --------------------------------------------------------
    # Verifica se o steghide consegue ler o formato da imagem.
    # Formatos suportados: JPEG baseline e BMP (não progressive,
    # não PNG, não WebP etc.). Usa o ImageMagick para converter
    # caso necessário, salvando em um arquivo temporário.
    # --------------------------------------------------------
    ext_lower=$(echo "${imagem##*.}" | tr '[:upper:]' '[:lower:]')
    imagem_para_embed="$imagem"
    tmp_convertido=""

    # Testa se steghide aceita a imagem diretamente
    teste_output=$(steghide info "$imagem" -p "" 2>&1)
    if echo "$teste_output" | grep -qi "not supported\|format\|error"; then
        # Precisa converter — avisa o usuário
        yad --title "$APP_NAME" \
            --image "$ICON_WARN" \
            --text "⚠️ O formato da imagem selecionada não é suportado diretamente pelo steghide.\n\n<b>A imagem será convertida automaticamente para JPEG</b> antes de ser usada como capa.\n\nO arquivo de saída salvo já estará no formato correto." \
            --button="Continuar:0" \
            --button="Cancelar:1" \
            --center --width=480 2>/dev/null
        [ $? -ne 0 ] && return

        tmp_convertido=$(mktemp /tmp/steghide_capa_XXXXXX.jpg)

        conv_output=$(convert "$imagem" \
            -sampling-factor 4:2:0 \
            -strip \
            -interlace None \
            -colorspace sRGB \
            -quality 92 \
            "$tmp_convertido" 2>&1)

        if [ $? -ne 0 ] || [ ! -s "$tmp_convertido" ]; then
            yad --title "$APP_NAME" \
                --image "$ICON_ERR" \
                --text "❌ <b>Falha ao converter a imagem.</b>\n\nDetalhe:\n<tt>$conv_output</tt>" \
                --button="Fechar:0" \
                --center --width=480 2>/dev/null
            rm -f "$tmp_convertido"
            return
        fi

        imagem_para_embed="$tmp_convertido"
    fi

    # Garante que o arquivo de saída termine em .jpg se a capa foi convertida
    if [ -n "$tmp_convertido" ] && [[ "$saida" != *.jpg ]] && [[ "$saida" != *.jpeg ]]; then
        saida="${saida%.* }.jpg"
    fi

    # Monta e executa o comando steghide
    if [ -n "$senha" ]; then
        CMD=(steghide embed -cf "$imagem_para_embed" -ef "$secreto" -sf "$saida" -p "$senha" -f)
    else
        CMD=(steghide embed -cf "$imagem_para_embed" -ef "$secreto" -sf "$saida" -p "" -f)
    fi

    output=$("${CMD[@]}" 2>&1)
    exit_code=$?

    # Remove temporário se criado
    [ -n "$tmp_convertido" ] && rm -f "$tmp_convertido"

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
# Função: sobre
# ------------------------------------------------------------
sobre() {
    yad --title "Sobre — $APP_NAME" \
        --image "$ICON_INFO" \
        --text "<span font='13' weight='bold'>SteghideGUI</span>\n\nScript desenvolvido para estudo por <b>Anderson Simões</b>\n\n🔗 <a href='https://www.linkedin.com/in/derso87'>LinkedIn: linkedin.com/in/derso87</a>\n📸 <a href='https://www.instagram.com/_anderson_simoes_/'>Instagram: @_anderson_simoes_</a>\n\n✨ Gerado com <a href='https://claude.ai/'>Claude</a>" \
        --button="Fechar:0" \
        --center --width=440 2>/dev/null
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
        "ℹ️   Sobre" \
        --button="Selecionar:0" \
        --button="ℹ️ Sobre:2" \
        --button="Sair:1" \
        --center --width=420 --height=280 2>/dev/null)

    codigo=$?

    # Botão "Sobre" (código 2)
    if [ $codigo -eq 2 ]; then
        sobre
        continue
    fi

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
        *Sobre*)       sobre       ;;
    esac
done
