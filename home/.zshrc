for f in ~/.config/zshrc/*; do
    [ -d "$f" ] || source "$f"
done

# Machine-local tweaks, deliberately outside the stow tree so they are neither committed nor rebuilt by apply.sh.
# Sourced last, so it wins over everything above.
if [ -f ~/.zshrc_custom ]; then
    source ~/.zshrc_custom
fi
