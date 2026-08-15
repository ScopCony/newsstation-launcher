# NewsStation Launcher

Publiczne startery do ręcznego uruchamiania prywatnego programu NewsStation.
Właściwy kod programu pozostaje w prywatnym repozytorium
`ScopCony/newsstation-backend`.

Starter przy pierwszym uruchomieniu pyta o system i token GitHuba tylko do
odczytu, pobiera prywatny program, przygotowuje Pythona 3.12, prosi o hasło do
zaszyfrowanego pakietu kluczy Google i Supabase oraz uruchamia menu NewsStation.
Przy kolejnych uruchomieniach sprawdza aktualizację i może skorzystać z ostatniej
działającej kopii lokalnej.

Program i jego lokalne wersje są przechowywane w podkatalogu `NewsStation`
systemowego folderu Pobrane/Downloads. Starter sam rozpoznaje właściwą nazwę i
położenie tego folderu na macOS, Windows 11 oraz Linuxie.

Jeżeli token GitHuba nie jest jeszcze zapisany, starter automatycznie otwiera
stronę tworzenia tokenu typu fine-grained z podstawowymi polami uzupełnionymi.
Użytkownik wybiera wyłącznie repozytorium `newsstation-backend`, generuje token
i wkleja go do startera. Przy kolejnych uruchomieniach strona nie jest otwierana.
Podczas wpisywania lub wklejania sekretów starter macOS/Linux pokazuje po jednej
gwieździe `*` za każdy przyjęty znak, nie ujawniając właściwej wartości.

Zaszyfrowany pakiet znajduje się wyłącznie w prywatnym repozytorium programu.
Hasło jest wymagane tylko przy pierwszym użyciu pakietu na danym komputerze oraz
po jego późniejszej zmianie. Samo hasło nie jest zapisywane.

## macOS lub Linux

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ScopCony/newsstation-launcher/main/Install-NewsStation.sh)"
```

## Windows 11

```powershell
irm "https://raw.githubusercontent.com/ScopCony/newsstation-launcher/main/Install-NewsStation.ps1" | iex
```

To publiczne repozytorium nie zawiera kluczy Google, Supabase, zaszyfrowanego
pakietu ani tokenów GitHuba. Na Linuxie starter nie tworzy automatycznego
harmonogramu.
