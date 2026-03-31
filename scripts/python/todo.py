import os

todo_list = ['','Show list','Add to list','Update list','Remove from list']
show_list_items = []

def show_todo():
    # displays the todo list
    
    print("\n******* TODO LIST *******")
    print("A simple python script for todo list\n") 

    for a in range(1, len(todo_list)):
        print(f"[{a}] {todo_list[a]}")
    print("\n")
    return

def show_list():
    # displat current tasks
    print("\n")
    print("Show list:")

    if len(show_list_items) == 0:
        print("Nothing to display here")
    else:
        pass
    return

def main():
    try:    
        while True:
            show_todo()
            
            user_input = int(input("Enter a number for todo >> "))    

            if user_input == 1:
                show_list()
            elif user_input == 2:
                print("Add to list")
            elif user_input == 3:
                print("Update list")
            elif user_input == 4:
                print("Remove from list")
            else:
                print("Please only select from the todo list\n")
                return
                            
            """
            Todo:
                - execute the selected todo task
            """

            print("\n")                  
    except ValueError:  # Specifically handle invalid integer input
        print("Please only select from the todo list\n")



if __name__ == "__main__":
    main()