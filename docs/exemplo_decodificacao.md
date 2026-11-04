# Exemplo de decodificação à mão

Este exemplo mostra como o processador interpreta uma instrução de 32 bits, campo por campo. Usamos a `mac` e, no final, a `sign`.

## 1. `mac x3, x1, x2` = `0x4020B1B3`

### Hexadecimal para binário

Cada dígito hexadecimal vira 4 bits:

```text
4    0    2    0    B    1    B    3
0100 0000 0010 0000 1011 0001 1011 0011
```

### Separando os campos (formato R)

```text
 31      25 24  20 19  15 14  12 11   7 6      0
+----------+------+------+------+------+--------+
|  funct7  |  rs2 |  rs1 |funct3|  rd  | opcode |
+----------+------+------+------+------+--------+
|  0100000 |00010 |00001 | 011  |00011 |0110011 |
```

| Campo | Bits | Valor | Significado |
|---|---|---|---|
| `opcode` | 6:0 | `0110011` | instrução do tipo R |
| `rd` | 11:7 | `00011` | registrador destino: `x3` |
| `funct3` | 14:12 | `011` | seleciona a operação dentro do tipo R |
| `rs1` | 19:15 | `00001` | primeiro operando: `x1` |
| `rs2` | 24:20 | `00010` | segundo operando: `x2` |
| `funct7` | 31:25 | `0100000` | seleciona a operação; o bit 30 vale 1 |

### Como a `CoreControlUnit` escolhe a operação

Para instruções R, a unidade de controle olha o par `{funct7[5], funct3}`. O `funct7[5]` é o bit 30 da instrução.

```text
{funct7[5], funct3} = {1, 011} = 4'b1011  ->  OP_MAC
```

Esse código não é usado por nenhuma instrução do RV32I base, por isso pôde ser reservado para a `mac`. Os outros códigos novos são:

| Instrução | `{funct7[5], funct3}` |
|---|---|
| `max` | `4'b1001` |
| `mul` | `4'b1010` |
| `mac` | `4'b1011` |
| `sign` | `4'b1100` |

### O que o hardware faz

1. O `RegisterFile` lê `x1` (porta 1) e `x2` (porta 2).
2. A **terceira porta de leitura** lê `instruction[11:7]`, ou seja, o valor atual de `rd` = `x3`. Ele vai para `alu_port_c`.
3. A ULA calcula `alu_o = alu_port_c + (alu_port_a * alu_port_b)`.
4. O resultado é escrito de volta em `x3`.

### Exemplo numérico

Suponha `x1 = 3`, `x2 = 4` e `x3 = 10` antes da instrução:

```text
x3 = x3 + x1 * x2 = 10 + 3 * 4 = 22
```

## 2. `sign x4, x1` = `0x4000C233`

```text
4    0    0    0    C    2    3    3
0100 0000 0000 0000 1100 0010 0011 0011
```

| Campo | Bits | Valor | Significado |
|---|---|---|---|
| `opcode` | 6:0 | `0110011` | tipo R |
| `rd` | 11:7 | `00100` | `x4` |
| `funct3` | 14:12 | `100` | |
| `rs1` | 19:15 | `00001` | `x1` |
| `rs2` | 24:20 | `00000` | não usado (`x0`) |
| `funct7` | 31:25 | `0100000` | bit 30 = 1 |

`{funct7[5], funct3}` = `{1, 100}` = `4'b1100`, que é `OP_SIGN`.

A `sign` usa só um operando, por isso o campo `rs2` fica em `x0` e é ignorado. O resultado é `-1` se `x1 < 0`, `0` se `x1 = 0` e `1` se `x1 > 0`.

## Observação

Estas codificações são próprias do projeto. O GCC e o `objdump` não as reconhecem, então os programas de teste (`*_test.txt`) estão escritos direto em hexadecimal.
