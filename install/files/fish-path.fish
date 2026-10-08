# Глобальный PATH для fish: ~/bin и ~/.local/bin (system-wide conf.d).
# fish /etc/profile не читает — нужен отдельный файл; fish_add_path
# сам дедуплицирует и не добавляет повторно при каждом входе.
fish_add_path $HOME/bin $HOME/.local/bin
