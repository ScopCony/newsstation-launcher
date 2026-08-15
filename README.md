# NewsStation Launcher

Publiczne startery do ręcznego uruchamiania prywatnego programu NewsStation.
Właściwy kod programu pozostaje w prywatnym repozytorium
`ScopCony/newsstation-backend`.

Starter przy pierwszym uruchomieniu pyta o system i potrzebne klucze, pobiera
prywatny program, przygotowuje Pythona 3.12 oraz uruchamia menu NewsStation.
Przy kolejnych uruchomieniach sprawdza aktualizację i może skorzystać z ostatniej
działającej kopii lokalnej.

Jeżeli token GitHuba nie jest jeszcze zapisany, starter automatycznie otwiera
stronę tworzenia tokenu typu fine-grained z podstawowymi polami uzupełnionymi.
Użytkownik wybiera wyłącznie repozytorium `newsstation-backend`, generuje token
i wkleja go do startera. Przy kolejnych uruchomieniach strona nie jest otwierana.
Podczas wpisywania lub wklejania sekretów starter macOS/Linux pokazuje po jednej
gwieździe `*` za każdy przyjęty znak, nie ujawniając właściwej wartości.

## macOS lub Linux

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ScopCony/newsstation-launcher/main/Install-NewsStation.sh)"
```

## Windows 11

```powershell
irm "https://raw.githubusercontent.com/ScopCony/newsstation-launcher/main/Install-NewsStation.ps1" | iex
```

Repozytorium nie zawiera kluczy Google, Supabase ani tokenów GitHuba. Na Linuxie
starter nie tworzy automatycznego harmonogramu.
