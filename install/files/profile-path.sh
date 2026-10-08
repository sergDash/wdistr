# Глобальный PATH для sh-оболочек (bash/sh login): ~/bin и ~/.local/bin.
# Источник wdistr, доставляется в /etc/profile.d/wdistr-path.sh.
case ":$PATH:" in
    *":$HOME/bin:"*) : ;;
    *) export PATH="$HOME/bin:$HOME/.local/bin:$PATH" ;;
esac
