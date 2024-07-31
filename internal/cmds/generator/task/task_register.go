/*
Copyright (c) 2023 OceanBase
ob-operator is licensed under Mulan PSL v2.
You can use this software according to the terms and conditions of the Mulan PSL v2.
You may obtain a copy of Mulan PSL v2 at:
         http://license.coscl.org.cn/MulanPSL2
THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
See the Mulan PSL v2 for more details.
*/

package main

import (
	"fmt"
	"go/ast"
	"go/parser"
	"go/token"
	"log"
	"os"
	"regexp"
	"strings"
	"text/template"
)

const genTemplate = `// Code generated by go generate; DO NOT EDIT.
package {{.PackageName}}

func init() {
{{- range .Tasks }}
	taskMap.Register(t{{.}}, {{.}})
{{- end }}
}
`

const taskNameGenTemplate = `// Code generated by go generate; DO NOT EDIT.
package {{.PackageName}}

import ttypes "github.com/oceanbase/ob-operator/pkg/task/types"

const (
{{- range .TasksWithName }}
	t{{.Task}} ttypes.TaskName = "{{.Name}}"
{{- end }}
)
`

type Task string

type TaskWithName struct {
	Task Task
	Name string
}

func camelCaseToSpaceStyle(s string) string {
	// var result string
	// for i, r := range s {
	// 	if i > 0 && unicode.IsUpper(r) {
	// 		result += " "
	// 	}
	// 	result += strings.ToLower(string(r))
	// }
	// return result
	re := regexp.MustCompile(`(?m)([a-z])([A-Z])`)
	spaceStr := strings.ToLower(re.ReplaceAllString(s, "${1} ${2}"))
	return spaceStr
}

func main() {
	if len(os.Args) != 2 {
		log.Fatalf("Usage: %s <source_file>", os.Args[0])
	}
	sourceFile := os.Args[1]

	fset := token.NewFileSet()
	node, err := parser.ParseFile(fset, sourceFile, nil, 0)
	if err != nil {
		log.Fatalf("Failed to parse source file: %v", err)
	}

	taskFuncs := []Task{}
	tasksWithName := []TaskWithName{}
	ast.Inspect(node, func(n ast.Node) bool {
		fn, ok := n.(*ast.FuncDecl)
		if !ok {
			return true
		}
		// Get return type of function and check whether it is a func(resource T) TaskError
		if len(fn.Type.Params.List) == 1 && len(fn.Type.Results.List) == 1 {
			if strings.HasSuffix(exprToString(fn.Type.Results.List[0].Type), "TaskError") {
				taskFuncs = append(taskFuncs, Task(fn.Name.Name))
				tasksWithName = append(tasksWithName, TaskWithName{
					Task: Task(fn.Name.Name),
					Name: camelCaseToSpaceStyle(fn.Name.Name),
				})
			}
		}

		return true
	})

	tmpl, err := template.New("registration").Parse(genTemplate)
	if err != nil {
		log.Fatalf("Failed to parse template: %v", err)
	}

	outputFile := sourceFile[:len(sourceFile)-3] + "_gen.go"

	f, err := os.Create(outputFile)
	if err != nil {
		log.Fatalf("Failed to create output file: %v", err)
	}
	defer f.Close()

	err = tmpl.Execute(f, struct {
		PackageName string
		Tasks       []Task
	}{
		PackageName: node.Name.Name,
		Tasks:       taskFuncs,
	})
	if err != nil {
		log.Printf("Failed to execute template: %v", err)
		return
	}

	nameTmpl, err := template.New("taskName").Parse(taskNameGenTemplate)
	if err != nil {
		log.Printf("Failed to parse template: %v", err)
		return
	}

	outputFile2 := sourceFile[:len(sourceFile)-3] + "name_gen.go"
	f2, err := os.Create(outputFile2)
	if err != nil {
		log.Printf("Failed to create output file: %v", err)
		return
	}
	defer f2.Close()

	err = nameTmpl.Execute(f2, struct {
		PackageName   string
		TasksWithName []TaskWithName
	}{
		PackageName:   node.Name.Name,
		TasksWithName: tasksWithName,
	})
	if err != nil {
		log.Printf("Failed to execute template: %v", err)
	}
}

func exprToString(expr ast.Expr) string {
	switch e := expr.(type) {
	case *ast.Ident:
		return e.Name
	case *ast.SelectorExpr:
		return exprToString(e.X) + "." + e.Sel.Name
	case *ast.StarExpr:
		return "*" + exprToString(e.X)
	default:
		return fmt.Sprintf("unknown(%T)", e)
	}
}