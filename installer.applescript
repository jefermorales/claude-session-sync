-- Claude Code Setup — AppleScript installer
-- Diálogos nativos macOS, sin terminal visible.

property kAppTitle : "Claude Code Setup"
property kGitHubIssues : "https://github.com/jefermorales/claude-session-sync/issues/new"
property kRepoURL : "https://github.com/jefermorales/claude-session-sync.git"
property kRepoDir : "$HOME/Developer/claude-session-sync"
property kLogFile : "$HOME/Library/Logs/claude-session-sync-install.log"

on run
	try
		welcomeScreen()
		set installState to detectInstalled()
		set toInstall to chooseToInstall(installState)
		if toInstall is {} then
			display dialog "Todas las dependencias ya están instaladas." & return & return & "Voy a verificar y reparar el setup multi-Mac igual." buttons {"Continuar"} default button "Continuar" with title kAppTitle
		else
			confirmInstall(toInstall, installState)
		end if
		runFullInstall(toInstall, installState)
		successScreen()
	on error errMsg number errNum
		if errNum is -128 then return -- Usuario canceló
		handleError(errMsg)
	end try
end run

------------------------------------------------------------------
-- Pantallas
------------------------------------------------------------------

on welcomeScreen()
	display dialog "Hola. Esto va a configurar tu Mac para usar Claude Code con tus chats, skills, agents y settings sincronizados entre máquinas vía Google Drive." & return & return & "Antes de continuar, asegurate de tener:" & return & "   • Google Drive Desktop instalado" & return & "   • Iniciada sesión con tu cuenta" & return & "   • Modo \"Replicar archivos\" activado" & return & return & "¿Empezamos?" buttons {"Cancelar", "Empezar"} default button "Empezar" with title kAppTitle with icon note
	preflight()
end welcomeScreen

on preflight()
	-- Detectar Drive instalado
	set driveFound to false
	try
		do shell script "ls -d \"$HOME/Mi unidad\" 2>/dev/null || ls -d \"$HOME/My Drive\" 2>/dev/null || ls -d \"$HOME/Library/CloudStorage\"/GoogleDrive-*/Mi*unidad 2>/dev/null || ls -d \"$HOME/Library/CloudStorage\"/GoogleDrive-*/My*Drive 2>/dev/null"
		set driveFound to true
	end try
	if not driveFound then
		display dialog "No encontré Google Drive Desktop en tu Mac." & return & return & "Instalalo desde:" & return & "https://www.google.com/drive/download/" & return & return & "Después de instalar y configurar (modo \"Replicar archivos\"), volvé a abrir este instalador." buttons {"Cerrar"} default button "Cerrar" with title kAppTitle with icon caution
		error number -128
	end if
end preflight

on successScreen()
	display dialog "¡Setup completo!" & return & return & "Próximos pasos:" & return & "   1. Abrí una nueva ventana de Terminal" & return & "   2. Ejecutá:" & return & "       cd \"$HOME/Mi unidad\"" & return & "       claude --resume" & return & return & "Vas a ver todos tus chats, skills, agents y settings sincronizados." buttons {"Listo"} default button "Listo" with title kAppTitle with icon note
end successScreen

on handleError(errMsg)
	-- Copiar log al portapapeles + abrir GitHub Issues
	try
		do shell script "cat " & quoted form of kLogFile & " | pbcopy"
	end try
	display dialog "Hubo un error en la instalación:" & return & return & errMsg & return & return & "Copiamos el log a tu portapapeles. ¿Querés abrir GitHub Issues ahora para reportarlo?" buttons {"Cerrar", "Abrir GitHub Issues"} default button "Abrir GitHub Issues" with title kAppTitle with icon stop
	if button returned of result is "Abrir GitHub Issues" then
		do shell script "open " & quoted form of kGitHubIssues
	end if
end handleError

------------------------------------------------------------------
-- Detección
------------------------------------------------------------------

on detectInstalled()
	set state to {xcodeInst:false, xcodeVer:"", brewInst:false, brewVer:"", nodeInst:false, nodeVer:"", claudeInst:false, claudeVer:"", jqInst:false, jqVer:""}
	try
		set p to do shell script "xcode-select -p"
		set xcodeInst of state to true
		set xcodeVer of state to p
	end try
	try
		set v to do shell script "command -v brew >/dev/null 2>&1 && brew --version | head -1"
		if v is not "" then
			set brewInst of state to true
			set brewVer of state to v
		end if
	end try
	try
		set v to do shell script "command -v node >/dev/null 2>&1 && node --version"
		if v is not "" then
			set nodeInst of state to true
			set nodeVer of state to v
		end if
	end try
	try
		set v to do shell script "command -v claude >/dev/null 2>&1 && claude --version 2>/dev/null | head -1"
		if v is not "" then
			set claudeInst of state to true
			set claudeVer of state to v
		end if
	end try
	try
		set v to do shell script "command -v jq >/dev/null 2>&1 && jq --version"
		if v is not "" then
			set jqInst of state to true
			set jqVer of state to v
		end if
	end try
	return state
end detectInstalled

------------------------------------------------------------------
-- Selección de qué instalar
------------------------------------------------------------------

on chooseToInstall(state)
	-- Items obligatorios faltantes
	set requiredMissing to {}
	if not xcodeInst of state then set end of requiredMissing to "Xcode Command Line Tools (git)"
	if not brewInst of state then set end of requiredMissing to "Homebrew"
	if not nodeInst of state then set end of requiredMissing to "Node.js + npm"
	if not claudeInst of state then set end of requiredMissing to "Claude Code CLI"

	-- Items opcionales
	set optionalsAvailable to {}
	if not jqInst of state then set end of optionalsAvailable to "jq (procesador JSON, hace cleanup más rápido)"
	set end of optionalsAvailable to "Cleanup al cerrar Claude (SessionEnd hook)"
	set end of optionalsAvailable to "Lock multi-Mac (warning si abierto en otra Mac)"

	-- Mostrar estado
	set statusMsg to "Estado actual:" & return
	if xcodeInst of state then
		set statusMsg to statusMsg & "  ✓ Xcode CLT (ya instalado)" & return
	else
		set statusMsg to statusMsg & "  ✗ Xcode CLT (falta)" & return
	end if
	if brewInst of state then
		set statusMsg to statusMsg & "  ✓ Homebrew " & brewVer of state & " (ya instalado)" & return
	else
		set statusMsg to statusMsg & "  ✗ Homebrew (falta)" & return
	end if
	if nodeInst of state then
		set statusMsg to statusMsg & "  ✓ Node.js " & nodeVer of state & " (ya instalado)" & return
	else
		set statusMsg to statusMsg & "  ✗ Node.js (falta)" & return
	end if
	if claudeInst of state then
		set statusMsg to statusMsg & "  ✓ Claude Code (ya instalado)" & return
	else
		set statusMsg to statusMsg & "  ✗ Claude Code (falta)" & return
	end if
	if jqInst of state then
		set statusMsg to statusMsg & "  ✓ jq " & jqVer of state & " (ya instalado)" & return
	end if

	display dialog statusMsg buttons {"Continuar"} default button "Continuar" with title kAppTitle with icon note

	-- Si hay opcionales, dejar elegir
	set chosenOptionals to {}
	if optionalsAvailable is not {} then
		set chosenOptionals to choose from list optionalsAvailable with prompt "¿Qué opcionales querés activar?" with title kAppTitle default items optionalsAvailable with multiple selections allowed OK button name "Aceptar" cancel button name "Cancelar"
		if chosenOptionals is false then error number -128
	end if

	-- Combinar obligatorios + opcionales
	set allToInstall to requiredMissing & chosenOptionals
	return allToInstall
end chooseToInstall

on confirmInstall(toInstall, state)
	set msg to "Vamos a hacer esto:" & return & return
	repeat with item_ in toInstall
		set msg to msg & "   + " & item_ & return
	end repeat
	set msg to msg & return & "¿Procedemos?"
	display dialog msg buttons {"Cancelar", "Sí, instalar"} default button "Sí, instalar" with title kAppTitle with icon note
end confirmInstall

------------------------------------------------------------------
-- Instalación
------------------------------------------------------------------

on runFullInstall(toInstall, state)
	-- Notificaciones para feedback sin bloquear
	repeat with item_ in toInstall
		set itemStr to item_ as string
		if itemStr contains "Xcode" then
			installXcode()
		else if itemStr contains "Homebrew" then
			installBrew()
		else if itemStr contains "Node.js" then
			installNode()
		else if itemStr contains "Claude Code" then
			installClaudeCode()
		else if itemStr starts with "jq " then
			installJq()
		end if
	end repeat

	-- Siempre: clonar repo y correr bootstrap
	cloneRepo()
	runBootstrap()
end runFullInstall

on installXcode()
	display notification "Instalando Xcode Command Line Tools..." with title kAppTitle
	try
		do shell script "xcode-select -p"
	on error
		do shell script "xcode-select --install"
		display dialog "Se abrió el instalador de Xcode Command Line Tools." & return & return & "Aceptá la instalación en la ventana de macOS que apareció y esperá ~5-10 min a que termine." & return & return & "Cuando termine, hacé clic en 'Listo' acá." buttons {"Listo"} default button "Listo" with title kAppTitle with icon note
		try
			do shell script "xcode-select -p"
		on error
			error "Xcode CLT no quedó instalado. Volvé a intentar."
		end try
	end try
end installXcode

on installBrew()
	display notification "Instalando Homebrew..." with title kAppTitle
	try
		do shell script "command -v brew >/dev/null"
	on error
		do shell script "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" >> " & kLogFile & " 2>&1" with administrator privileges
		-- Cargar brew en PATH
		do shell script "[ -x /opt/homebrew/bin/brew ] && eval \"$(/opt/homebrew/bin/brew shellenv)\" || [ -x /usr/local/bin/brew ] && eval \"$(/usr/local/bin/brew shellenv)\""
	end try
end installBrew

on installNode()
	display notification "Instalando Node.js + npm..." with title kAppTitle
	do shell script "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\" && brew install node >> " & kLogFile & " 2>&1"
end installNode

on installClaudeCode()
	display notification "Instalando Claude Code CLI..." with title kAppTitle
	do shell script "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\" && npm install -g @anthropic-ai/claude-code >> " & kLogFile & " 2>&1"
end installClaudeCode

on installJq()
	display notification "Instalando jq..." with title kAppTitle
	do shell script "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\" && brew install jq >> " & kLogFile & " 2>&1"
end installJq

on cloneRepo()
	display notification "Clonando claude-session-sync..." with title kAppTitle
	do shell script "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\" && if [ -d " & kRepoDir & "/.git ]; then git -C " & kRepoDir & " pull --quiet; else mkdir -p $(dirname " & kRepoDir & ") && git clone --quiet " & kRepoURL & " " & kRepoDir & "; fi >> " & kLogFile & " 2>&1"
end cloneRepo

on runBootstrap()
	display notification "Configurando setup multi-Mac..." with title kAppTitle
	do shell script "export PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\" && bash " & kRepoDir & "/bootstrap-claude.sh >> " & kLogFile & " 2>&1"
end runBootstrap
