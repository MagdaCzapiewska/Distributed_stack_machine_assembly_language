global core
extern get_value
extern put_value

MINUS_EIGHT equ 0xfffffffffffffff8
MINUS_SIXTEEN equ 0xfffffffffffffff0
MINUS_TWENTY_FOUR equ 0xffffffffffffffe8
MINUS_THIRTY_TWO equ 0xffffffffffffffe0

section .data

align 8
threads: times N dq N

align 8
values: times N dq 0


section .text

; Funkcja core wykonuje operacje na stosie, które odczytuje z ciągu instrukcji danego jako argument

; Argumenty funkcji core:
; rdi - numer rdzenia
; rsi - wskaźnik na napis ASCIIZ. Definiuje obliczenie, jakie ma wykonać rdzeń

; Wartości zwracane:
; rax - wartość z wierzchołka stosu po zakończeniu wykonywania obliczeń

; Modyfikuje rejestry rax, rdi, rsi, r9, rcx
align 16
core:
    push    r15
    mov     r15, rsp                    ; Zapamiętuję wskaźnik czubka stosu z początku wywołania + 8
    push    rbx                         ; Zapamiętuję na stosie wartości rejestrów rbx i rbp,
    push    rbp                         ; żeby zapamiętać w nich numer rdzenia i wskaźnik na obliczenie.
                                        ; Mam gwarancję, że funkcje wywoływane call nie zmienią wartości
    mov     rbx, rdi                    ; tych rejestrów.
    mov     rbp, rsi

    push    r12
    push    r13
    mov     r12, 0x0                    ; W rejestrze r12 przechowuję pozycję w obliczeniu, którą odczytuję.

.loop_for_computation:
    mov     al, BYTE [rbp + 1 * r12]    ; Kopiuję instrukcję z obliczenia do jednobajtowego rejestru al.
.check_if_exit:
    cmp     al, 0x0                     ; Obliczenie jest zakończone znakiem '\0', którego kod ASCII to 0.
    jnz      .check_if_digit

.exit:
    mov     rdi, r15                    ; Wiem, że w r15 jest zamapiętany adres czubka stosu z początku funkcji core
                                        ; tuż po wrzuceniu na stos zawartości rejestru r15.
    mov     r15, [rdi]                  ; Przywracam wartości rejestrów r15, rbx, rbp, r12, r13.
    mov     rbx, [rdi + MINUS_EIGHT]
    mov     rbp, [rdi + MINUS_SIXTEEN]
    mov     r12, [rdi + MINUS_TWENTY_FOUR]
    mov     r13, [rdi + MINUS_THIRTY_TWO]
    pop     rax                         ; Oczekiwana wartość zwracana to wartość z czubka stosu.
    add     rdi, 0x8                    ; Obliczam rsp z początku wywołania funkcji core.
    mov     rsp, rdi                    ; rsp nie powinno się zmienić w wyniku wywołania funkcji core,
                                        ; żeby osiągalny był adres powrotu.
    ret

.check_if_digit:
    cmp     al, '0'
    jb      .check_if_plus
    cmp     al, '9'
    ja      .check_if_plus

    mov     rdi, 0x0                    ; Zeruję rejestr rdi, żeby potem działać tylko na jego najmłodszym bajcie.
    mov     dil, al                     ; W dil umieszczam 1-bajtowy kod ASCII znaku obliczenia.
    sub     dil, '0'                    ; Odejmuję kod ASCII znaku '0'.
    push    rdi

    jmp     .next_index

.check_if_plus:
    cmp     al, '+'
    jnz     .check_if_star

    pop     rdi                         ; Zdejmuję ze stosu tylko jedną wartość
    add     [rsp], rdi                  ; Dodaję ją do wartości obecnie na czubku stosu

    jmp     .next_index

.check_if_star:
    cmp     al, '*'
    jnz     .check_if_minus

    pop     rdi                         ; Zdejmuję 2 wartości ze stosu i wrzucam wynik przemnożenia ich przez siebie.
    pop     rax
    mul     rdi
    push    rax

    jmp     .next_index

.check_if_minus:
    cmp     al, '-'
    jnz     .check_if_n

    neg     QWORD [rsp]                 ; Wykonuję negację arytmetyczną wartości na czubku stosu.

    jmp     .next_index

.check_if_n:
    cmp     al, 'n'
    jnz     .check_if_B

    push    rbx                         ; Wrzucam na stos numer rdzenia

    jmp     .next_index

.check_if_B:
    cmp     al, 'B'
    jnz     .check_if_C
    pop     rax                         ; Wartość zdjęta z czubka stosu informuje, o ile pozycji należy się przesunąć
    cmp     QWORD [rsp], 0x0            ; Przesunięcie następuje, gdy wartość z aktualnego czubka stosu != 0.
    jz      .next_index

    add     r12, rax                    ; Przesunięcie o zadaną ilość pozycji indeksu wskazującego operację obliczenia.

    jmp     .next_index

.check_if_C:
    cmp     al, 'C'
    jnz     .check_if_D

    pop     rax                         ; Pozbywam się wartości z czubka stosu.

    jmp     .next_index

.check_if_D:
    cmp     al, 'D'
    jnz     .check_if_E

    push    QWORD [rsp]                 ; Duplikuję wartość z czubka stosu.

    jmp     .next_index

.check_if_E:
    cmp     al, 'E'
    jnz     .check_if_S

    pop     rax                         ; Zamieniam miejscami 2 wartości z czubka stosu.
    pop     rdi
    push    rax
    push    rdi

    jmp     .next_index

.next_index:
    inc     r12
    jmp     .loop_for_computation

.check_if_S:
    cmp     al, 'S'
    jnz     .P_or_G

    pop     rax                         ; Wątek n zdejmuje ze swojego stosu wartość m.
    pop     rdi                         ; Potem zdejmuje ze stosu wartość, której chce się pozbyć.
    cmp     rax, rbx                    ; Jeśli n == m, następuje przejście do kolejnej operacji
                                        ; (sekwencja "nS" potraktowana jako C)
    jz      .next_index

; Najpierw wątek n czeka na to, aby w jego komórce była wartość == N
; (żeby wiedział, że wszystko, co było do odebrania przy wcześniejszej "wymianie", odpowiedni wątek odebrał).
; Instrukcja mov jest atomowa (w tym przypadku to odczyt z tablicy globalnej).

    lea     r9, [rel threads]           ; W r9 jest adres zerowego elementu tablicy threads
    lea     rcx, [rel values]           ; W rcx jest adres zerowego elementu tablicy values

.waiting_for_N_in_my_cell:
    mov     rsi, [r9 + rbx*8]           ; Odczytaj threads[n]
    cmp     rsi, N                      ; Czy threads[n] == N?
    jnz     .waiting_for_N_in_my_cell

; Jak wątek n odczytał N, wpisuje do tablicy values wartość, jaką ma dla wątku m, a do tablicy threads wpisuje m
; (w tej kolejności, bo jeśli wątek m zobaczy, że n chce się z nim wymienić, powinien móc odebrać już poprawną wartość).
.found_N:
    mov     [rcx + rbx*8], rdi          ; values[n] = wartość, którą wątek n chce przekazać wątkowi m
    mov     [r9 + rbx*8], rax           ; threads[n] = m

; Wątek n czeka, aż wątek m będzie chciał mu coś dać.
.waiting_for_m:
    mov     rsi, [r9 + rax*8]           ; Odczytaj threads[m]
    cmp     rsi, rbx                    ; Czy threads[m] == n?
    jnz     .waiting_for_m

    mov     rsi, [rcx + rax*8]          ; Odczytaj values[m].
    push    rsi                         ; Wrzuć na swój stos wartość z values[m].
    mov     qword [r9 + rax*8], N       ; Zaznacz w threads[m], że odebrane.
    jmp     .next_index

.P_or_G:
    mov     rdi, rbx                    ; Argument n dla funkcji put_value lub get_value.
    cmp     al, 'P'
    jnz     .testing_rsp
    pop     rsi                         ; Zdejmuję ze stosu argument w dla funkcji put_value.

; Żeby sprawdzić, czy wartość rsp jest podzielna przez 16, wystarczy sprawdzić, czy 4 najmłodsze bity
; 64-bitowej reprezentacji rsp są wszystkie zerami.
.testing_rsp:
    mov     r13, 0x000000000000000f     ; 64-bitowa reprezentacja r13 to 0 na starszych 60 bitach i 1 na najmłodszych 4.
    and     r13, rsp                    ; Jeśli rsp podzielny przez 16, to w wyniku koniunkcji bitowej w r13 będzie 0.

    jz      .r13_ready
    mov     r13, 0x8                    ; Jeśli r13 != 0, to od rsp należy odjąć 0x8.

.r13_ready:
    sub     rsp, r13                    ; Jeśli rsp % 16 != 0, odejmuję 8 - stos rośnie w kierunku mniejszych adresów.
    cmp     al, 'P'
    jnz     .G
    call    put_value
    add     rsp, r13                    ; Dodaję 8 - chcę mieć na górze stosu tę wartość,
    jmp     .next_index                 ; która była przed odjęciem 8 od rsp.
.G:
    call    get_value
    add     rsp, r13
    push    rax                         ; Wrzucam na stos wartość zwróconą przez funkcję get_value.
    jmp     .next_index