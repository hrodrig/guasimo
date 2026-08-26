# Appendix — Code-review assertiveness (verbatim evidence)

> Companion to `04-models.md` → *"Code-review assertiveness (qualitative, 2026-08-25)"*.
> This file holds the full, unedited outputs of the peer-review probe so the
> summary in `04-models.md` stays short and this stays reproducible. Method
> and the three verbatim responses are below.

## Method

A single **Go prompt** (the benchmark prompt) was answered in rounds:

1. **Ornith 9B (Q6_K, stock)** answered the prompt.
2. A second model (**MiniMax M3**) rewrote the answer more strictly.
3. **Ornith 9B** reviewed MiniMax M3's rewrite — conceded what was better, and
   caught the trailing-data bug MiniMax M3 left open.
4. A third model (**Kimi K3**) graded Ornith's original output 8.5/10 and
   raised three refinements.
5. **Ornith 9B** responded to Kimi's three points — accepted the two fair
   ones, pushed back on the weak third, and fused a final corrected version.

The prompt (also `scripts/bench.prompt.txt` on the reference box):

> Write a Go function that reads a JSON file containing a list of users
> (name, email, age) and returns the average age of users over 30, handling
> missing or malformed files gracefully. Output only the Go code, no
> explanation.

## Round 1 — Ornith 9B (original answer)

```go
package main

import (
    "encoding/json"
    "fmt"
    "os"
)

type User struct {
    Name  string `json:"name"`
    Email string `json:"email"`
    Age   int    `json:"age"`
}

// AverageAgeOver30 reads a JSON file containing a list of users and returns the
// average age of users older than 30. Missing or malformed files are handled
// gracefully by returning an error instead of panicking.
func AverageAgeOver30(path string) (float64, error) {
    data, err := os.ReadFile(path)
    if err != nil {
        return 0, fmt.Errorf("failed to read file %q: %w", path, err)
    }

    var users []User
    if err := json.Unmarshal(data, &users); err != nil {
        return 0, fmt.Errorf("failed to parse JSON from %q: %w", path, err)
    }

    var sum float64
    count := 0
    for _, u := range users {
        if u.Age > 30 {
            sum += float64(u.Age)
            count++
        }
    }

    if count == 0 {
        return 0, fmt.Errorf("no users over 30 found")
    }

    return sum / float64(count), nil
}
```

## Round 2 — MiniMax M3 (strict rewrite)

```go
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
)

// User is one record in the JSON list.
type User struct {
	Name  string `json:"name"`
	Email string `json:"email"`
	Age   int    `json:"age"`
}

// AverageAgeOver30 reads a JSON file containing a list of users
// ({"name","email","age"} objects) and returns the average age of
// users whose age is strictly greater than 30.
//
// Error handling:
//   - Missing/unreadable file  -> wrapped error including the path.
//   - Malformed JSON           -> wrapped parse error.
//   - Empty file or no matches -> (0, nil) by mathematical convention
//     (average of an empty set). Callers that need to distinguish
//     "no input" from "no matches" should validate upstream.
func AverageAgeOver30(path string) (float64, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, fmt.Errorf("open %q: %w", path, err)
	}
	defer f.Close()

	dec := json.NewDecoder(f)
	var users []User
	if err := dec.Decode(&users); err != nil {
		if errors.Is(err, io.EOF) {
			return 0, nil
		}
		return 0, fmt.Errorf("parse %q: %w", path, err)
	}

	var sum float64
	var count int
	for _, u := range users {
		if u.Age > 30 {
			sum += float64(u.Age)
			count++
		}
	}
	if count == 0 {
		return 0, nil
	}
	return sum / float64(count), nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: users <path-to-json>")
		os.Exit(2)
	}
	avg, err := AverageAgeOver30(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("average age of users over 30: %.2f\n", avg)
}
```

## Round 4 — Kimi K3 (evaluation, 8.5/10)

> Es una respuesta de muy buena calidad (8.5/10). Cumple el prompt, es
> idiomática en Go y maneja errores correctamente.
>
> **Lo que hace bien:** manejo de errores robusto (`fmt.Errorf` con `%w` para
> permitir unwrapping, no hace panic, distingue archivo inexistente de JSON
> malformado); Go moderno (`os.ReadFile` en vez del obsoleto `ioutil`);
> lógica correcta (filtra `> 30` estrictamente, usa `float64` para evitar
> división entera, valida división por cero); estructura clara (struct con
> tags JSON correctos, firma limpia).
>
> **Lo que podría mejorar (detalles menores):**
> 1. El error cuando `count == 0` — defendible, pero muchos lo considerarían
>    un falso positivo (`(0, nil)` sería más graceful).
> 2. Comentarios excesivos para un prompt "output only code, no explanation".
> 3. No valida edades negativas o nulas (los ignora silenciosamente).
>
> **Veredicto:** código de producción digno, percentil superior; los puntos
> son refinamientos, no defectos.

## Round 5 — Ornith 9B (response to Kimi K3)

```text
Mi lectura honesta de los tres puntos:

1. El error en count == 0 — punto justo. Devolver un error cuando el archivo
   es válido pero no hay coincidencias puede ser un "falso positivo". La
   palabra clave del prompt es gracefully, y un archivo con todos los usuarios
   jóvenes no es un error de E/S ni de parsing. (0, nil) es más coherente.
   Un matiz: mi versión original era internamente consistente (tanto [] como
   un archivo con solo jóvenes devolvían el mismo error), pero eso no la hacía
   correcta — trataba dos situaciones distintas de la misma manera. Para una
   función que "devuelve un promedio", (0, nil) es lo más limpio.

2. Comentarios excesivos — punto justo. El prompt pidió "Output only the Go
   code, no explanation". Un doc-comment multilínea es explicativo y lo
   incluí. Fallo menor de seguimiento de instrucciones, no de calidad.

3. Validación de edades negativas/nulas — el punto más débil. Aquí Kimi
   exagera un poco. El filtro u.Age > 30 ya excluye negativos, cero y
   cualquier valor ≤ 30; no contaminan el promedio. La única anomalía real es
   "age":"forty" (tipo incorrecto), que sí produce error de parseo. Validar
   rangos sería un extra opcional, no un defecto, y cambiaría la semántica:
   un age negativo no es malformado, es dato erróneo.

Veredicto: Kimi acierta en 1 y 2; el 3 es observación de estilo, no defecto.
El código original era bueno; la versión ajustada resuelve los dos puntos
legítimos. Si quieres cubrir el punto 3 de verdad, habría que validar el rango
explícitamente, pero eso ya es una decisión de negocio más allá del prompt.
```

The fused final version Ornith returned for round 5 (accepting Kimi's points
1 and 2, picking up MiniMax M3's `json.Decoder`/`io.EOF`/`(0, nil)`):

```go
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
)

type User struct {
	Name  string `json:"name"`
	Email string `json:"email"`
	Age   int    `json:"age"`
}

// AverageAgeOver30 reads a JSON file of users and returns the average age of
// those strictly older than 30. A missing or malformed file yields an error;
// a valid file with no matching users returns (0, nil).
func AverageAgeOver30(path string) (float64, error) {
	f, err := os.Open(path)
	if err != nil {
		return 0, fmt.Errorf("open %q: %w", path, err)
	}
	defer f.Close()

	dec := json.NewDecoder(f)
	var users []User
	if err := dec.Decode(&users); err != nil {
		if errors.Is(err, io.EOF) {
			return 0, nil
		}
		return 0, fmt.Errorf("parse %q: %w", path, err)
	}

	var sum float64
	count := 0
	for _, u := range users {
		if u.Age > 30 {
			sum += float64(u.Age)
			count++
		}
	}
	if count == 0 {
		return 0, nil
	}
	return sum / float64(count), nil
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: users <path-to-json>")
		os.Exit(2)
	}
	avg, err := AverageAgeOver30(os.Args[1])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("average age of users over 30: %.2f\n", avg)
}
```
