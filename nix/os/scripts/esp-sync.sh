for target in /boot*; do
    [ "$target" = "/boot" ] && continue

    if mountpoint -q "$target"; then
        echo "Syncing /boot -> $target"
        rsync -a --delete --inplace /boot/ "$target/" 2>&1 || echo "Syncing to $target failed"
    else
        echo "Skipping $target (not mounted)"
    fi
done