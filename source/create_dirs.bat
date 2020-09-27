@echo off
ECHO Creating Live Editor folder in Documents\FIFA 21
SET fifa_docs=%HOMEDRIVE%\Users\%USERNAME%\Documents\FIFA 21\
SET ct_path=%fifa_docs%Cheat Table\
mkdir "%ct_path%data\"
ECHO A | xcopy cache "%ct_path%cache" /E /i