# Miniacelerador de Rede Neural Integrado ao RISC-V (Projeto da Unidade 3)

## 🎯 Objetivos da aula
* Compreender os princípios de projeto e implementação de um **miniacelerador de hardware dedicado** em SystemVerilog para operações de Inteligência Artificial.
* Dominar o modelo matemático e computacional de um **neurônio artificial básico** com duas entradas, dois pesos e função de ativação **ReLU**.
* Aprender a projetar circuitos puramente **combinacionais** para computação paralela de multiplicação e soma de inteiros com sinal.
* Projetar uma **interface de comunicação e controle** entre o processador RISC-V e o acelerador utilizando **instruções customizadas**.
* Solucionar o gargalo de largura de banda de operandos do RISC-V (passagem de 4 operandos através de instruções de 2 registradores fonte).
* Definir o fluxo sistemático de desenvolvimento, simulação em testbench, integração arquitetural e validação de hardware.

---

## 📚 Conteúdo principal

### 1. Modelo Matemático do Neurônio Artificial em Hardware
* **Conceito:** O miniacelerador implementa a computação básica de inferência de um neurônio artificial composto por duas entradas ponderadas e uma função de ativação não linear.
* **Explicação:** Em redes neurais artificiais, o neurônio calcula a soma ponderada dos sinais de entrada multiplicados por seus respectivos pesos sinápticos e submete o resultado a uma função de ativação. A função de ativação escolhida é a **ReLU** (*Rectified Linear Unit*), que zera qualquer valor acumulado negativo e preserva valores positivos ou nulos.
* **Equação Matemática:**
  $$y = \max(0, x_1 w_1 + x_2 w_2)$$

  *Legenda dos termos da equação:*
  * $y$: Sinal de saída calculado pelo neurônio artificial, codificado como um inteiro de 32 bits com sinal.
  * $x_1$: Primeira entrada de dados, representada como um inteiro de 8 bits com sinal.
  * $w_1$: Primeiro peso sináptico associado à entrada $x_1$, representado como um inteiro de 8 bits com sinal.
  * $x_2$: Segunda entrada de dados, representada como um inteiro de 8 bits com sinal.
  * $w_2$: Segundo peso sináptico associado à entrada $x_2$, representado como um inteiro de 8 bits com sinal.
  * $x_1 w_1$ e $x_2 w_2$: Multiplicações aritméticas paralelas dos pares de entrada e peso.
  * $+$: Soma aritmética dos produtos das multiplicações parciais.
  * $\max(0, \text{valor})$: Função de ativação ReLU (se $\text{soma} < 0$, o resultado é $0$; caso contrário, mantém-se a $\text{soma}$).
* **Exemplo:** Se $x_1 = 3$, $w_1 = 4$, $x_2 = 2$ e $w_2 = -10$:
  * $x_1 w_1 = 3 \times 4 = 12$
  * $x_2 w_2 = 2 \times (-10) = -20$
  * Soma $= 12 + (-20) = -8$
  * Saída $y = \max(0, -8) = 0$ (retificado pela ReLU).
* **Importante:** A saída possui **32 bits com sinal** para evitar *overflow* de acumulações e permitir compatibilidade direta com a largura padrão dos registradores do núcleo RV32I.

---

### 2. Etapa 1 — Miniacelerador Combinacional (2 Multiplicadores)
* **Conceito:** Implementação em SystemVerilog do módulo de hardware que processa diretamente os quatro operandos sem necessidade de estruturas de temporização.
* **Explicação:** Nesta etapa inicial, o circuito é puramente **combinacional**:
  * Não é necessário utilizar sinal de *clock*, memórias internas ou máquinas de estados (unidade de controle).
  * O módulo recebe quatro portas de entrada de 8 bits ($x_1, w_1, x_2, w_2$) com sinal (`signed [7:0]`).
  * Realiza as duas multiplicações em paralelo em hardware dedicado.
  * Soma os dois produtos resultantes com extensão de sinal adequada.
  * Aplica a lógica da ReLU verificando o bit de sinal mais significativo (MSB) do resultado ou por meio de um operador condicional ternário.
  * Disponibiliza a resposta em uma porta de saída de 32 bits com sinal (`signed [31:0]`).
* **Exemplo:** Em SystemVerilog, a lógica central combinacional pode ser expressa como:
  ```systemverilog
  module neural_accelerator (
      input  logic signed [7:0]  x1,
      input  logic signed [7:0]  w1,
      input  logic signed [7:0]  x2,
      input  logic signed [7:0]  w2,
      output logic signed [31:0] y
  );
      logic signed [15:0] prod1, prod2;
      logic signed [31:0] sum;

      always_comb begin
          prod1 = x1 * w1;
          prod2 = x2 * w2;
          sum   = 32'(prod1) + 32'(prod2);
          y     = (sum < 0) ? 32'sd0 : sum; // Função ReLU
      end
  endmodule
  ```
* **Importante:** A validação nesta etapa exige o desenvolvimento de um **testbench dedicado** que teste exaustivamente casos positivos, negativos (onde a ReLU deve zerar a saída) e limites de representação de 8 bits.

---

### 3. Etapa 2 — Integração Arquitetural ao Processador RISC-V
* **Conceito:** Acoplamento do miniacelerador ao processador RISC-V desenvolvido na Unidade 2 como uma unidade de execução funcional especializada.
* **Explicação:** O acelerador deixa de ser um bloco isolado e passa a fazer parte do caminho de dados do processador:
  * O processador deve ser capaz de selecionar e acionar a execução do acelerador.
  * O acelerador precisa receber os operandos fornecidos pelo processador e disponibilizar o resultado calculado de volta para o banco de registradores.
  * **Simplificações permitidas pelo projeto:** Não é necessário implementar um novo banco de registradores exclusivo, memória RAM dedicada, pipeline complexo no acelerador ou uma rede neural profunda com múltiplas camadas.
* **Importante:** É obrigatório documentar detalhadamente no relatório técnico a interface física e lógica entre o núcleo RISC-V e o acelerador.

---

### 4. O Desafio de Envio de Operandos e as Instruções Customizadas
* **Conceito:** Como a ISA RISC-V opera instruções no formato padrão com no máximo dois registradores fonte (`rs1` e `rs2`), o envio simultâneo de quatro operandos ($x_1, w_1, x_2, w_2$) exige uma estratégia de interface específica.
* **Explicação:** A solução oficial definida nas diretrizes do projeto utiliza **registradores internos no acelerador** combinados com **duas novas instruções customizadas**:
  1. **`acc_load rs1, rs2`:** Envia um par de operandos (uma entrada e um peso) para os registradores temporários do acelerador.
  2. **`acc_exec rd`:** Dispara o cálculo do neurônio artificial utilizando os quatro operandos previamente armazenados e escreve o resultado final de 32 bits no registrador de destino `rd` do RISC-V.
* **Mapeamento de Execução em Assembly:**
  * Executa-se o primeiro `acc_load` para carregar o par $(x_1, w_1)$.
  * Executa-se o segundo `acc_load` para carregar o par $(x_2, w_2)$.
  * Executa-se a instrução `acc_exec` que aciona as duas multiplicações em paralelo, a soma, a ReLU e grava o valor em `rd`.
* **Exemplo de Programa Assembly de Teste:**
  ```assembly
  # Configuração dos operandos nos registradores do RISC-V
  li a0, 5        # x1 = 5
  li a1, 3        # w1 = 3
  li a2, 4        # x2 = 4
  li a3, -2       # w2 = -2

  # 1º Envio: carrega x1 e w1 no acelerador
  acc_load a0, a1

  # 2º Envio: carrega x2 e w2 no acelerador
  acc_load a2, a3

  # Execução: calcula max(0, 5*3 + 4*(-2)) = max(0, 15 - 8) = 7
  acc_exec t0     # t0 recebe o resultado 7
  ```
* **Importante:** A identificação dessas instruções customizadas reutiliza a metodologia da Unidade 2, alocando novos opcodes ou campos `funct3`/`funct7` não utilizados da base inteira do RISC-V.

---

## 🔑 Conceitos-chave
* **Miniacelerador de Hardware:** Bloco de silício dedicado a computar operações matemáticas específicas de forma rápida e eficiente em consumo energético.
* **Neurônio Artificial em Hardware:** Circuito integrado composto por unidades de multiplicação em paralelo, somador aritmético e estágio de ativação.
* **ReLU (Rectified Linear Unit):** Função de ativação definida por $f(x) = \max(0, x)$, essencial para introduzir não linearidades em redes neurais.
* **Instrução Customizada (*Custom Instruction*):** Instrução estendida adicionada à ISA padrão para disparar diretamente rotinas em coprocessadores ou aceleradores.
* **`acc_load`:** Instrução customizada que transfere 2 operandos de registradores do RISC-V para registradores de espera no acelerador.
* **`acc_exec`:** Instrução customizada que aciona a computação combinacional/aritmética do acelerador e retorna o resultado para o banco de registradores.
* **Circuito Combinacional:** Circuito digital cujas saídas dependem estritamente das entradas atuais, dispensando registradores de estado ou sinais de clock (Etapa 1).

---

## 🧠 Relações entre os conceitos
* **Casamento Algoritmo-Hardware:** Em vez de a CPU executar um laço de software lento com múltiplas instruções de multiplicação (`mul`) e desvios condicionais (`bge`/`blt`) para calcular a ReLU, o miniacelerador resolve toda a equação do neurônio em hardware com latência drasticamente reduzida.
* **Limitação da ISA vs. Registradores Internos:** A limitação física do formato de instrução do RISC-V (apenas 2 registradores fonte `rs1` e `rs2`) atua como causa direta para a necessidade de incluir registradores internos no acelerador, dividindo o processo em etapas de carga (`acc_load` sequenciais) e disparo (`acc_exec`).
* **Etapa 1 vs. Etapa 2:** A Etapa 1 valida a fidelidade matemática do circuito puramente combinacional em bancada de testes (*testbench* isolado). A Etapa 2 resolve o controle, a decodificação de instruções e a temporização de sinais integrando o bloco ao processador completo.

---

## ⚖️ Comparações

### Tabela 1: Implementação do Neurônio: Software (RV32I) vs. Miniacelerador Dedicado
| Característica | Emulação em Software Puro (RV32I) | Miniacelerador Integrado de Hardware |
| :--- | :--- | :--- |
| **Instruções necessárias** | Múltiplas instruções (`mul`, `add`, `bge`/`blt` para ReLU). | 2 instruções `acc_load` + 1 instrução `acc_exec`. |
| **Consumo de ciclos** | Dezenas de ciclos de clock por neurônio. | Pouquíssimos ciclos (execução combinacional paralela). |
| **Operações de multiplicação** | Sequenciais (uma por vez na ULA/extensão M). | 2 multiplicações executadas simultaneamente em paralelo. |
| **Uso da ULA principal** | Monopoliza a ULA do processador durante todo o cálculo. | ULA permanece livre; cálculo ocorre no coprocessador. |

### Tabela 2: Comparativo das Instruções Customizadas de Controle do Acelerador
| Instrução | Registradores Fonte | Registrador Destino | Papel no Hardware |
| :---: | :---: | :---: | :--- |
| **`acc_load rs1, rs2`** | `rs1` (entrada), `rs2` (peso) | Nenhum (apenas estado interno) | Salva o par de operandos no buffer/registrador interno do acelerador. |
| **`acc_exec rd`** | Nenhum (lê buffers internos) | `rd` (resultado de 32 bits) | Computa a soma ponderada com ReLU e escreve o resultado no banco da CPU. |

---

## 🚀 Resumo e Fluxo de Desenvolvimento do Projeto

O fluxo de desenvolvimento da Unidade 3 é estruturado em fases incrementais para garantir validação passo a passo e facilidade de depuração:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      FLUXO DE DESENVOLVIMENTO DO PROJETO                     │
└─────────────────────────────────────────────────────────────────────────────┘

  [ FASE 1: PROJETO DO MÓDULO COMBINACIONAL (Etapa 1) ]
     │
     ├── 1.1 Especificar portas de entrada (signed 8-bit) e saída (signed 32-bit)
     ├── 1.2 Implementar os 2 multiplicadores paralelos e o somador em SystemVerilog
     ├── 1.3 Implementar a função de corte não linear ReLU
     └── 1.4 Criar Testbench isolado (testar casos positivos, negativos e saturações)
     │
     ▼
  [ FASE 2: DEFINIÇÃO DA INTERFACE COM A ISA RISC-V (Etapa 2) ]
     │
     ├── 2.1 Definir opcodes e campos funct3/funct7 para `acc_load` e `acc_exec`
     ├── 2.2 Projetar os registradores internos do acelerador para armazenar x1, w1, x2, w2
     └── 2.3 Projetar a máquina de estados simples / lógica de controle de carga dos pares
     │
     ▼
  [ FASE 3: INTEGRAÇÃO AO CAMINHO DE DADOS E UNIDADE DE CONTROLE ]
     │
     ├── 3.1 Instanciar o módulo do acelerador no caminho de dados (Datapath)
     ├── 3.2 Modificar a Unidade de Controle para decodificar `acc_load` e `acc_exec`
     ├── 3.3 Conectar barramento de saída do acelerador ao multiplexador de escrita em rd
     └── 3.4 Conectar saídas dos registradores rs1 e rs2 às entradas do acelerador
     │
     ▼
  [ FASE 4: VALIDAÇÃO EM ASSEMBLY E RELATÓRIO TÉCNICO ]
     │
     ├── 4.1 Escrever programa em assembly RISC-V aplicando múltiplos vetores de teste
     ├── 4.2 Simular a integração completa no simulador (ModelSim / Questa / EDA Playground)
     ├── 4.3 Capturar formas de onda demonstrando carregamento e cálculo correto
     └── 4.4 Redigir relatório técnico detalhando decisões arquiteturais e critérios
```

---

## 📝 Resumo para revisão
* **Objetivo do projeto:** Criar e integrar ao núcleo RISC-V um miniacelerador combinacional de hardware para calcular a inferência de um neurônio artificial: $y = \max(0, x_1 w_1 + x_2 w_2)$.
* **Larguras de dados:** 4 entradas/pesos de **8 bits com sinal** e saída final de **32 bits com sinal**.
* **Etapa 1:** Acelerador isolado, puramente **combinacional** (sem clock, sem memória, sem unidade de controle), validado via testbench.
* **Etapa 2:** Integração com o RISC-V da Unidade 2, definindo mecanismo de comunicação e controle.
* **Solução para 4 operandos:** Criação de buffers internos no acelerador e 2 instruções customizadas:
  * `acc_load rs1, rs2`: executada duas vezes para armazenar $(x_1, w_1)$ e $(x_2, w_2)$.
  * `acc_exec rd`: aciona a multiplicação, soma e ReLU, gravando a saída em `rd`.
* **Critérios de pontuação:** Etapa 1 (3,5 pts), Etapa 2 (3,5 pts), Testes e validação (1,5 pts), Relatório e decisões arquiteturais (1,5 pts) — Total: 10,0 pontos.
