# Integração do miniacelerador neural ao RISC-V

## Objetivo

Este documento explica a primeira integração do módulo `NeuralAccelerator` com o processador monociclo. A implementação calcula um neurônio com duas entradas, dois pesos e ativação ReLU:

```text
y = max(0, x1*w1 + x2*w2)
```

As quatro entradas são signed de 8 bits e a saída é signed de 32 bits. O RISC-V tem dois registradores fonte por instrução; por isso, são necessárias duas instruções para entregar os dois pares ao acelerador e uma terceira para escrever o resultado no banco de registradores.

## Visão geral da interface

Foram definidos dois formatos de instrução no opcode custom-0, `0001011`:

| Instrução | `funct3` | Operação |
|---|---|---|
| `acc_load rs1, rs2` | `000` | Lê os oito bits menos significativos de `rs1` e `rs2` e guarda o par no acelerador. |
| `acc_exec rd` | `001` | Seleciona o resultado `y` do acelerador para writeback no registrador `rd`. |

A sequência de uso é:

```text
acc_load x1, x2    # primeiro par: entrada x1 e peso w1
acc_load x3, x4    # segundo par: entrada x2 e peso w2
acc_exec x5        # calcula, aplica ReLU e grava em x5
```

Nesse exemplo os nomes de registrador da instrução são fontes da CPU: o conteúdo de `x1` é usado como entrada neural `x1`, o conteúdo de `x2` como peso `w1`, o conteúdo de `x3` como entrada `x2` e o conteúdo de `x4` como peso `w2`.

## Alterações por arquivo

### `src/single_cycle_processor/NeuralAccelerator.sv`

O módulo que antes recebia diretamente quatro operandos independentes foi adaptado para a interface integrada ao processador:

- Recebe `clk_i`, `reset_i`, `load_enable_i` e dois operandos signed de 8 bits (`operand_a_i`, `operand_b_i`).
- Mantém internamente `x1`, `w1`, `x2` e `w2`.
- Usa `load_second_pair` para alternar qual par será carregado. Após reset, a primeira carga vai para `(x1,w1)`, a segunda para `(x2,w2)` e a terceira volta a substituir o primeiro par.
- Na borda de subida, quando `load_enable_i` está ativo, grava os operandos no par selecionado.
- Em lógica combinacional, calcula os dois produtos em paralelo, soma-os com extensão para 32 bits e aplica ReLU.

```systemverilog
prod1 = x1 * w1;
prod2 = x2 * w2;
sum   = 32'(prod1) + 32'(prod2);
y     = (sum < 0) ? 32'sd0 : sum;
```

O sinal interno `sum` é a soma antes da ReLU. A saída `y` é o resultado depois da ReLU. Por isso, no segundo caso de teste, `sum=-26` mas `y=0`.

### `src/single_cycle_processor/CoreControlUnit.sv`

- Adiciona o decode do opcode custom-0 `7'b0001011`.
- Define `accelerator_load_enable_o` como zero por padrão para que instruções que não são `acc_load` não alterem os pares internos.
- Com `funct3=000`, ativa `accelerator_load_enable_o`; não habilita escrita de registrador nem escrita de memória.
- Com `funct3=001`, habilita escrita no banco de registradores e seleciona `RD_MUX_ACCEL` para o writeback.
- As outras opções de `funct3` não carregam operandos nem escrevem resultado.

O decode atual usa o opcode e `funct3`; não valida todos os outros campos da codificação.

### `src/single_cycle_processor/risc_v_32_i_pkg.sv`

Adiciona `RD_MUX_ACCEL` ao enum `write_data_select_e`. Esse novo valor permite que o mux de writeback selecione o resultado do acelerador sem reutilizar ou alterar a saída da ALU principal. A largura de seleção de 3 bits comporta esse valor adicional.

### `src/single_cycle_processor/ProcessorCore.sv`

- Liga `reg_source_1[7:0]` e `reg_source_2[7:0]` às duas entradas do acelerador. A seleção de oito bits é deliberada: os registradores do RISC-V têm 32 bits, mas as entradas do módulo são signed de 8 bits.
- Liga clock, reset e o sinal de carga gerado pela unidade de controle.
- Guarda a saída em `accelerator_result`.
- Adiciona `RD_MUX_ACCEL` ao mux de writeback. Quando a instrução é `acc_exec`, `reg_data` recebe `accelerator_result`, e o banco de registradores grava esse dado em `rd`.

### `src/single_cycle_processor/InstructionMemory.sv`

No estado atual usado para este teste, o `$readmemh` carrega diretamente `neural_test.txt`. Portanto, para executar outro programa é necessário trocar o nome nessa linha e recompilar. O argumento `+TEST` do testbench seleciona o arquivo esperado; ele não escolhe o programa de instruções.

### `neural_test.txt` e `expected/neural_test_expected.txt`

O primeiro arquivo contém o programa hexadecimal que exercita a interface. O segundo especifica os registradores, palavras de memória e store de conclusão que o testbench deve verificar.

## Teste, instrução por instrução

| Palavra | Interpretação | Estado/resultado |
|---|---|---|
| `00500093` | `addi x1,x0,5` | `x1=5` |
| `00300113` | `addi x2,x0,3` | `x2=3` |
| `00400193` | `addi x3,x0,4` | `x3=4` |
| `FFE00213` | `addi x4,x0,-2` | `x4=0xFFFFFFFE` |
| `0020800B` | `acc_load x1,x2` | Guarda `(entrada=5,peso=3)` como primeiro par. |
| `0041800B` | `acc_load x3,x4` | Guarda `(entrada=4,peso=-2)` como segundo par. |
| `0000128B` | `acc_exec x5` | `sum=5*3 + 4*(-2)=7`; `y=7`; grava `x5=7`. |
| `00502023` | `sw x5,0(x0)` | Grava `MEM[0]=7`. |
| `FFB00093` | `addi x1,x0,-5` | `x1=0xFFFFFFFB` (os oito bits baixos são `0xFB`, signed `-5`). |
| `00400113` | `addi x2,x0,4` | `x2=4` |
| `00200193` | `addi x3,x0,2` | `x3=2` |
| `FFD00213` | `addi x4,x0,-3` | `x4=0xFFFFFFFD` |
| `0020800B` | `acc_load x1,x2` | Guarda `(-5,4)` como primeiro par. |
| `0041800B` | `acc_load x3,x4` | Guarda `(2,-3)` como segundo par. |
| `0000130B` | `acc_exec x6` | `sum=(-5)*4 + 2*(-3)=-26`; ReLU produz `y=0`; grava `x6=0`. |
| `006020A3` | `sw x6,1(x0)` | Grava `MEM[1]=0` e encerra o teste. |

A memória de dados simplificada do projeto usa o endereço diretamente como índice de palavra. Assim, os stores em `0` e `1` são índices de palavras, não endereços de byte de uma implementação RISC-V completa.

## Resultado esperado

O arquivo `expected/neural_test_expected.txt` verifica:

```text
x1 = 0xFFFFFFFB  # -5
x2 = 4
x3 = 2
x4 = 0xFFFFFFFD  # -3
x5 = 7
x6 = 0
MEM[0] = 7
MEM[1] = 0
```

A linha `COMPLETE 1 00000000` informa ao testbench que o programa terminou quando o store de conclusão escreve zero na palavra de memória 1.

Resultado observado no ModelSim após a integração:

```text
neural_test TEST: completion detected after 16 cycles
neural_test TEST: PASS
```

## Como compilar e simular

Execute a partir da raiz do repositório, compilando primeiro o pacote. Inclua `NeuralAccelerator.sv` na lista de fontes:

```bash
vlog -work work -sv \
  src/single_cycle_processor/risc_v_32_i_pkg.sv \
  src/single_cycle_processor/NeuralAccelerator.sv \
  src/single_cycle_processor/ArithmeticLogicUnit.sv \
  src/single_cycle_processor/ComparatorUnit.sv \
  src/single_cycle_processor/CoreControlUnit.sv \
  src/single_cycle_processor/DataMemory.sv \
  src/single_cycle_processor/ImmediateSignExtend.sv \
  src/single_cycle_processor/InstructionMemory.sv \
  src/single_cycle_processor/LoadStoreUnit.sv \
  src/single_cycle_processor/ProcessorCore.sv \
  src/single_cycle_processor/RegisterFile.sv \
  tb/top.sv

vsim -c work.top +TEST=neural_test -do "run -all; quit -f"
```

`+TEST=neural_test` faz o testbench ler `expected/neural_test_expected.txt`. O programa executado é o que estiver configurado no `$readmemh` de `InstructionMemory.sv`.

## Sinais úteis para a waveform

Depois de iniciar `vsim work.top +TEST=neural_test`, adicione sinais com:

```tcl
add wave /top/clk /top/reset
add wave -radix hexadecimal /top/instruction_address /top/instruction_data
add wave /top/write_enable /top/data_address /top/write_data
add wave /top/PrCore/accelerator_load_enable
add wave /top/PrCore/neural_accelerator/load_second_pair
add wave /top/PrCore/neural_accelerator/x1
add wave /top/PrCore/neural_accelerator/w1
add wave /top/PrCore/neural_accelerator/x2
add wave /top/PrCore/neural_accelerator/w2
add wave -radix signed /top/PrCore/neural_accelerator/sum
add wave -radix signed /top/PrCore/neural_accelerator/y
add wave /top/PrCore/reg_write_enable /top/PrCore/reg_data
run -all
wave zoom full
```

No primeiro cálculo, `sum` e `y` valem `7`. No segundo, `sum` vale `-26` (`0xFFFFFFE6`) e `y` vale `0`. `write_enable` é a escrita da memória e só ativa nos dois `sw`; `reg_write_enable` é a escrita no banco de registradores, incluindo `acc_exec`.

## Limitações da primeira integração

- Cada operando é truncado aos oito bits menos significativos do registrador fonte. Os valores precisam caber no intervalo signed de 8 bits, de `-128` a `127`; fora desse intervalo, o byte truncado é reinterpretado como signed.
- O acelerador alterna o destino das cargas, mas não verifica se exatamente duas cargas ocorreram antes de `acc_exec`. Executar cedo usa o par ainda não carregado (zero após reset); executar cargas ímpares/sobrando pode deixar um par antigo no estado.
- O controle volta ao primeiro par a cada reset. Não há instrução de reset/limpeza separada para o acelerador.
- `y` é combinacional e calculado continuamente a partir dos pares armazenados; `acc_exec` seleciona esse resultado para gravar em `rd`, não inicia uma máquina de estados interna.
- O teste verifica funcionalidade ponta a ponta e ReLU, mas não mede área, frequência nem consumo de energia.
