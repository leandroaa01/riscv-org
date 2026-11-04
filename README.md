# RV32I com instruções customizadas para IA

![Processador monociclo](./docs/images/Single_cycle_processor.png)

Projeto da Unidade 2 de DIM0129 (DIMAp/UFRN, 2026.2). Partimos do processador RV32I monociclo de [Hariesh Anbalagan](https://github.com/HarieshAnbalagan/RV32I), escrito em SystemVerilog, e adicionamos as três instruções pedidas no enunciado (`max`, `mac` e `sign`) e também uma `mul`.

O enunciado está em [docs/DIM0129_-_RISC-V_III.pdf](docs/DIM0129_-_RISC-V_III.pdf).

## Autores
Este projeto foi desenvolvido por Carlos Alberto de Lima Neto (<carlos.neto.087@ufrn.edu.br>), Leandro Andrade de Araujo (<leandro.andrade.401@ufrn.edu.br>), Luiz Guilherme Carvalho Viana(<luiz.viana.097@ufrn.edu.br>) e Osvaldo Heitor de Andrade Tavares de Souza(< heitor.andrade.102@ufrn.edu.br>).

## Instruções adicionadas

| Instrução | Semântica | Relação com IA |
|---|---|---|
| `mul rd, rs1, rs2` | `rd = rs1 * rs2` (32 bits baixos) | Base para a `mac` |
| `max rd, rs1, rs2` | `rd = max(rs1, rs2)`, com sinal | Pooling / redução |
| `mac rd, rs1, rs2` | `rd = rd + rs1 * rs2` | Redes neurais, convolução |
| `sign rd, rs1` | `rd = -1` se `rs1 < 0`, `0` se `rs1 = 0`, `1` se `rs1 > 0` | Ativação, classificação, quantização |

### Codificação

Todas usam o formato R (opcode `0110011`) com `funct7 = 0100000`. A `CoreControlUnit` decodifica as instruções R pelo par `{funct7[5], funct3}`, e cada instrução nova ocupou um código que não existe no RV32I base:

| Instrução | funct3 | `{funct7[5], funct3}` | Exemplo |
|---|---|---|---|
| `mul` | `010` | `4'b1010` | `0x4020A1B3` = `mul x3, x1, x2` |
| `max` | `001` | `4'b1001` | `0x402091B3` = `max x3, x1, x2` |
| `mac` | `011` | `4'b1011` | `0x4020B1B3` = `mac x3, x1, x2` |
| `sign` | `100` | `4'b1100` | `0x4000C233` = `sign x4, x1` (`rs2 = x0`) |

Os códigos que ainda estão livres ficam anotados em [code_free.md](code_free.md).

Essas codificações são próprias deste projeto. A `mul` não segue a `mul` da extensão M (`funct7 = 0000001`, `funct3 = 000`), e a `sign` tem a mesma codificação do `xnor` da extensão Zbb. Por isso o GCC não gera essas instruções e o `objdump` não as reconhece.

### Mudanças no hardware

| Arquivo | Mudança |
|---|---|
| `risc_v_32_i_pkg.sv` | `OP_MUL`, `OP_MAX`, `OP_MAC` e `OP_SIGN` no enum `alu_select_e` |
| `CoreControlUnit.sv` | Novos casos no decode das instruções R |
| `ArithmeticLogicUnit.sv` | As quatro operações novas e a porta `alu_port_c_i`, usada pela `mac` |
| `RegisterFile.sv` | Terceira porta de leitura (`read_address_3_i`), que lê o valor atual de `rd` para a `mac` |
| `ProcessorCore.sv` | Liga o valor lido de `rd` à porta C da ULA |

`mul`, `max` e `sign` usam o caminho de dados que toda instrução R já tem. A `mac` é a única que precisou de um operando a mais. Os detalhes estão em [docs/mac_operation.md](docs/mac_operation.md), [docs/max_operation.md](docs/max_operation.md) e [docs/sign_operation.md](docs/sign_operation.md).

## Estrutura

- `src/single_cycle_processor/`: RTL do processador
- `tb/top.sv`: testbench que confere os resultados sozinho
- `*_test.txt`, `L_S_type.txt`: programas de teste em hexadecimal
- `expected/`: resultados esperados de cada teste
- `Data_Memory_Load.txt`: conteúdo inicial da memória de dados
- `docs/`: enunciado, documentação das instruções e imagens

## Simulação

No ModelSim:

1. Adicione ao projeto todos os arquivos `.sv` de `src/single_cycle_processor/` e o `tb/top.sv`.
2. Compile tudo (Compile All).
3. Simule:

```text
vsim work.top
add wave -r /*
run -all
```

Para trocar de teste, mude dois lugares:

- o arquivo carregado pelo `$readmemh` em `src/single_cycle_processor/InstructionMemory.sv`;
- o `test_name` padrão em `tb/top.sv`, ou passe `+TEST=<nome>` para o `vsim`. Esse nome só escolhe o arquivo de resultados esperados, não o programa.

O projeto também roda no Icarus Verilog 12 (`iverilog -g2012`), desde que a linha do SRA/SRL em `CoreControlUnit.sv` receba um cast para `alu_select_e`. O Icarus recusa a linha sem o cast; o ModelSim aceita.

## Testes

O testbench lê `expected/<teste>_expected.txt` e executa o programa até o store de conclusão (a linha `COMPLETE` do arquivo). Depois compara os registradores e a memória com o esperado e imprime `PASS` ou uma linha `MISMATCH` para cada diferença.

| Teste | O que verifica | Ciclos |
|---|---|---|
| `L_S_type` | Loads e stores do RV32I: byte, meia palavra e palavra, com e sem sinal | 18 |
| `mul_test` | `6 * 7 = 42` | 4 |
| `max_test` | `max(-5, 9) = 9`, comparação com sinal | 4 |
| `mac_test` | `3 + 5 * 7 = 38` | 5 |
| `mac_test2` | Soma `x1 + x2`, acumula o produto com MAC (`12 + 5 * 7 = 47`) e subtrai `x2` (`x4 = 40`) | 6 |
| `mac_test3` | Soma, MAC em `x4` (`12 + 5 * 7 = 47`), subtração (`47 - 2 = 45`) e novo MAC (`45 + 7 * 2 = 59`); grava `59` na memória | 8 |
| `sign_test` | Negativo, zero, positivo, `0x80000000`, `0x7FFFFFFF`, `0x40000000`, `rs1 = x0` e `rd = rs1` | 17 |
| `R_type` | Instruções R do RV32I base (`add`, `sub`, `sll`, `slt`, `sltu`, `xor`, `srl`, `sra`, `or`, `and`), programa enviado pela professora | 12 |

O `R_type` não termina com um store, então precisa rodar no modo de contagem de instruções. No modo padrão, o testbench espera um store que nunca acontece e termina com `timeout`:

```text
vsim work.top +TEST=R_type +TERMINATION=instruction_count +INSTRUCTION_COUNT=12
```

Nesse modo o testbench imprime uma linha `RETIRE` por instrução e, no fim, compara os registradores com `expected/R_type_expected.txt`.

## Limitações

- O processador é só monociclo. Não há versão multiciclo nem com pipeline.
- A `DataMemory` usa o endereço direto como índice de palavra (64 palavras). Por isso os testes fazem stores em `1(x0)`, `2(x0)` etc.
- Load e store de byte e de meia palavra usam sempre a parte baixa da palavra. O store grava a palavra inteira, completada com zeros, porque a `DataMemory` não usa o strobe.

## Licença e créditos

GNU GPL v3, ver [LICENSE](LICENSE). Processador base de [Hariesh Anbalagan](https://github.com/HarieshAnbalagan/RV32I). Enunciado da Profa. Monica Pereira.
