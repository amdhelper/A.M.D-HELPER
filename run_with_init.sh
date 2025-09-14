#!/bin/bash
# This script handles the initial, one-time setup for A.M.D-Helper.
# It is idempotent, cancellable, and restartable.
# It forces a dark theme for all UI elements for accessibility.

APP_DIR="/usr/share/a.m.d-helper"
FLAG_DIR="$HOME/.config/a.m.d-helper"
FLAG_FILE="$FLAG_DIR/init_done"

# Set the GTK theme to a dark variant for all zenity dialogs.
export GTK_THEME=Adwaita:dark

# --- Idempotency Check ---
# If setup is already done, just launch the main application and exit.
if [ -f "$FLAG_FILE" ]; then
    exec "$APP_DIR/tray.sh"
fi

# --- Pre-flight check ---
if ! command -v zenity &> /dev/null; then
    echo "Error: 'zenity' is not installed. Please install it to proceed with the initial setup." >&2
    echo "You can try running 'sudo apt-get install zenity'." >&2
    # Try to run non-visually as a last resort
    exec "$APP_DIR/tray.sh" &
    exit 1
fi

# --- User Interaction ---
# Inform the user and get their confirmation before starting the download.
zenity --question --title="A.M.D-Helper Setup" --text="Welcome to A.M.D-Helper!\n\nTo enable screen reading (OCR), we need to download language models. This is a one-time setup.\n\nDo you want to start the download now?" --width=350 --no-markup
if [ $? -ne 0 ]; then
    # User clicked "No" or closed the dialog.
    zenity --info --text="Setup postponed. You can start it again later by running the application shortcut." --width=300 --no-markup
    exit 0
fi

# --- The Download Process ---
# Run the main script and pipe its output to a cancellable progress bar.
if ( "$APP_DIR/tray.sh" &> /dev/null ) | zenity --progress --title="Initializing A.M.D-Helper" --text="Downloading models, please wait...\nThis window will close automatically when finished." --pulsate --auto-close --width=350; then
    # This block executes if zenity exits with status 0 (i.e., it was not cancelled).
    # The tray icon should now be running in the background, started by tray.sh.
    # We can show a success message.
    zenity --info --text="Setup complete! A.M.D-Helper is now running in your system tray." --width=300 --no-markup
else
    # This block executes if the user cancels the progress dialog.
    # We need to kill the background download process.
    pkill -f "$APP_DIR/tray.py"
    zenity --warning --text="Setup was cancelled. The download was stopped.\n\nYou can run the setup again later by clicking the application shortcut." --width=300 --no-markup
fi

exit 0
