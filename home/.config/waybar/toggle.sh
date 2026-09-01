#!/usr/bin/env bash

if [ -f $HOME/.config/ml4w/settings/waybar-disabled ]; then
    rm $HOME/.config/ml4w/settings/waybar-disabled
else
    touch $HOME/.config/ml4w/settings/waybar-disabled
fi
$HOME/.config/waybar/launch.sh &
